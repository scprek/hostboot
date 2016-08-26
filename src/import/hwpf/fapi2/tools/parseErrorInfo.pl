#!/usr/bin/perl
# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/import/hwpf/fapi2/tools/parseErrorInfo.pl $
#
# OpenPOWER HostBoot Project
#
# Contributors Listed Below - COPYRIGHT 2015,2016
# [+] International Business Machines Corp.
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# IBM_PROLOG_END_TAG
#
# @file   parseErrorInfo.pl
# @brief  This perl script will parse HWP Error XML files and generate required
#         FAPI code to create and error log and add FFDC to the error.
#
# *HWP HWP Owner: N/A
# *HWP FW Owner: Thi Tran <thi@us.ibm.com>
# *HWP Team: N/A
# *HWP Level: 1
# *HWP Consumed by: HB
#
# Usage:
# parseErrorInfo.pl <output dir> <filename1> <filename2> ...

use strict;

#------------------------------------------------------------------------------
# Set PREFERRED_PARSER to XML::Parser. Otherwise it uses XML::SAX which contains
# bugs that result in XML parse errors that can be fixed by adjusting white-
# space (i.e. parse errors that do not make sense).
#------------------------------------------------------------------------------
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

#------------------------------------------------------------------------------
# Specify perl modules to use
#------------------------------------------------------------------------------
use Digest::MD5 qw(md5_hex);
use XML::Simple;
my $xml = new XML::Simple (KeyAttr=>[]);

# Uncomment to enable debug output
use Data::Dumper;
use Getopt::Long;


my @eiObjects = ();
my $target_ffdc_type = "fapi2::Target<T>";
my $buffer_ffdc_type = "fapi2::buffer";
my $variable_buffer_ffdc_type = "fapi2::variable_buffer";
my $ffdc_type = "fapi2::ffdc_t";
my $mcast_type = "fapi2::mcast_t";

# We want to keep the signatures for the ffdc gathering hwp so that
# we can create members of the proper types for the ffdc classes.
my %signatures = ("proc_extract_pore_halt_ffdc" => ["por_base_state",
                                                    "por_halt_type_t",
                                                    "por_ffdc_offset_t"],
                  "proc_example" => ["uint32_t","uint8_t"],
                  "proc_extract_pore_base_ffdc" => ["por_base_state", "por_sbe_base_state"],
                  "proc_tp_collect_dbg_data" => [$target_ffdc_type],
                  "p9_collect_some_ffdc" => ["uint32_t","uint8_t"],
    );

# There are some names used in the XML files which exist in either
# c++ keywords (case, for example) or macros (DOMAIN). The one's which
# cause problems and need to be changed are here.
#
# DOMAIN is defined to 1 in math.h
my %mangle_names = ("DOMAIN" => "FAPI2_DOMAIN");

# A list of deprecated elements. These will report messages to the
# user, and not define anything. They have not been found to be used,
# but that doesn't mean they're not ...
my %deprecated = ("RC_PROCPM_PMCINIT_TIMEOUT" => "CHIP_IN_ERROR is defined as a callout procedure");

#------------------------------------------------------------------------------
# Print Command Line Help
#------------------------------------------------------------------------------
my $arg_empty_ffdc = undef;
my $arg_local_ffdc = undef;
my $arg_output_dir = undef;
my $arg_use_variable_buffers = undef;

# Get the options from the command line - the rest of @ARGV will
# be filenames
GetOptions("empty-ffdc-classes" => \$arg_empty_ffdc,
           "local-ffdc" => \$arg_local_ffdc,
           "output-dir=s" => \$arg_output_dir,
           "use-variable-buffers" => \$arg_use_variable_buffers);

my $numArgs = $#ARGV + 1;
if (($numArgs < 1) || ($arg_output_dir eq undef))
{
    print ("Usage: parseErrorInfo.pl [--empty-ffdc-classes] [--use-variable-buffers] --output-dir=<output dir> <filename1> <filename2> ...\n");
    print ("  This perl script will parse HWP Error XML files and creates\n");
    print ("  the following files:\n");
    print ("  - hwp_return_codes.H.      HwpReturnCode enumeration (HWP generated errors)\n");
    print ("  - hwp_error_info.H.        Error information (used by FAPI_SET_HWP_ERROR\n");
    print ("                             when a HWP generates an error)\n");
    print ("  - collect_reg_ffdc_regs.H. File containing registers used by collectRegFfdc() \n");
    print ("  - set_sbe_error.H.    Macro to create an SBE error\n");
    print ("  The --empty-ffdc-classes option is for platforms which don't collect ffdc.\n");
    exit(1);
}

#------------------------------------------------------------------------------
# Hashes containing error names/enum-values
#------------------------------------------------------------------------------
my %errNameToValueHash;
my %errValuePresentHash;

#------------------------------------------------------------------------------
# Hashes containing ffdc names/enum-values
#------------------------------------------------------------------------------
my %ffdcNameToValueHash = ();
my %ffdcValuePresentHash = ();

#------------------------------------------------------------------------------
# Subroutine that checks if an entry exists in an array. If it doesn't exist
# then it is added. The index of the entry within the array is returned
#------------------------------------------------------------------------------
sub addEntryToArray
{
    my ($arrayref, $entry ) = @_;

    my $match = 0;
    my $index = 0;

    foreach my $element (@$arrayref)
    {
        if ($element eq $entry)
        {
            $match = 1;
            last;
        }
        else
        {
            $index++;
        }
    }

    if (!($match))
    {
        push(@$arrayref, $entry);
    }

    return $index;
}

#------------------------------------------------------------------------------
# Subroutine that figures out an error enum value from an error name and stores
# it in global hashes
#------------------------------------------------------------------------------
sub setErrorEnumValue
{
    my $name = $_[0];

    #--------------------------------------------------------------------------
    # Check that the error name is not a duplicate
    #--------------------------------------------------------------------------
    if (exists($errNameToValueHash{$name}))
    {
        # Two different errors with the same name!
        print ("fapiParseErrorInfo.pl ERROR. Duplicate error name ", $name, "\n");
        exit(1);
    }

    #--------------------------------------------------------------------------
    # Figure out the error enum-value. This is a hash value generated from
    # the error name. A hash is used for Cronus so that if a HWP is not
    # recompiled against a new eCMD/Cronus version where the errors have
    # changed then there will not be a mismatch in error values.
    # This is a 24bit hash value because FAPI has a requirement that the
    # top byte of the 32 bit error value be zero to store flags indicating
    # the creator of the error
    #--------------------------------------------------------------------------
    my $errHash128Bit = md5_hex($name);
    my $errHash24Bit = substr($errHash128Bit, 0, 6);

    #--------------------------------------------------------------------------
    # Check that the error enum-value is not a duplicate
    #--------------------------------------------------------------------------
    if (exists($errValuePresentHash{$errHash24Bit}))
    {
        # Two different errors generate the same hash-value!
        print ("fapiParseAttributeInfo.pl ERROR. Duplicate error hash value\n");
        exit(1);
    }

    #--------------------------------------------------------------------------
    # Update the hashes with the error name and ID
    #--------------------------------------------------------------------------
    $errValuePresentHash{$errHash24Bit} = 1;
    $errNameToValueHash{$name} = $errHash24Bit;
}

#------------------------------------------------------------------------------
# Subroutine that figures out an FFDC ID value from an FFDC name and stores it
# in global hashes for use when creating the enumeration of FFDC IDs
#------------------------------------------------------------------------------
sub setFfdcIdValue
{
    my $name = $_[0];

    #--------------------------------------------------------------------------
    # Check that the FFDC name is not a duplicate
    #--------------------------------------------------------------------------
    if (exists($ffdcNameToValueHash{$name}))
    {
        # Two different FFDCs with the same name!
        print ("fapiParseErrorInfo.pl ERROR. Duplicate FFDC name ", $name, "\n");
        exit(1);
    }

    #--------------------------------------------------------------------------
    # Figure out the FFDC enum-value. This is a hash value generated from
    # the FFDC name.
    #--------------------------------------------------------------------------
    my $ffdcHash128Bit = md5_hex($name);
    my $ffdcHash32Bit = substr($ffdcHash128Bit, 0, 8);

    #--------------------------------------------------------------------------
    # Check that the error enum-value is not a duplicate
    #--------------------------------------------------------------------------
    if (exists($ffdcValuePresentHash{$ffdcHash32Bit}))
    {
        # Two different FFDCs generate the same hash-value!
        print ("fapiParseAttributeInfo.pl ERROR. Duplicate FFDC hash value\n");
        exit(1);
    }

    #--------------------------------------------------------------------------
    # Update the hashes with the error name and ID
    #--------------------------------------------------------------------------
    $ffdcValuePresentHash{$ffdcHash32Bit} = 1;
    $ffdcNameToValueHash{$name} = $ffdcHash32Bit;
}

#------------------------------------------------------------------------------
# Subroutine to create ffdc methods
#------------------------------------------------------------------------------
sub addFfdcMethod
{
    my $methods = shift;
    my $ffdc_uc = shift;
    my $class_name = shift;
    my $type = shift;
    my $objectNumber = shift;

    # Remove the leading *_
    $class_name = (split (/_/, $class_name, 2))[1];

    # If we didn't get a type passed in, this element will get an ffdc_t pair.
    $type = $ffdc_type if ($type eq undef);

    # Mangle the uppercase name if needed
    $ffdc_uc = $mangle_names{$ffdc_uc} if ($mangle_names{$ffdc_uc} ne undef);

    my $key = $ffdc_uc.$type;
    my $key_target = $ffdc_uc.$target_ffdc_type;
    my $key_ffdc = $ffdc_uc.$ffdc_type;

    # Check to see if this element already has been recorded with this
    # type or a target type. Note the effect we're shooting for here is
    # to define the member if it's not been defined before *or* it's
    # changing from an ffdc_t to a target due to other information in the xml
    return if ($methods->{$key}{type} eq $type);
    return if ($methods->{$key_target}{type} eq $target_ffdc_type);

    # Just leave if this is a variable_buffer as we're not supporting that.
    return if (($type eq $variable_buffer_ffdc_type) && ($arg_use_variable_buffers eq undef));

    # Set the proper type, and clear out any previous members/methods if
    # we're going from an ffdc_t to a target.
    $methods->{$key}{type} = $type;
    delete $methods->{$key_ffdc} if ($type eq $target_ffdc_type);


    my $method = "";
    my $method_body = "";

    # If we're generating empty classes, not using an argument name will avoid the unused parameter warnings
    my $param = ($arg_empty_ffdc eq undef) ? "i_value" : "";

    if ($type eq $ffdc_type)
    {
        $method =      "\ttemplate< typename T >\n";
        $method  .=      "\tinline $class_name& set_$ffdc_uc(const T& $param)\n";

        if($arg_local_ffdc eq undef)
        {
            $method_body  =  "    {$ffdc_uc.ptr() = &i_value; $ffdc_uc.size() =";
            $method_body  .= " fapi2::getErrorInfoFfdcSize(i_value); return *this;}\n\n";
            $methods->{$key}{member} = "$ffdc_type $ffdc_uc;";
            $methods->{$objectNumber}{localvar} = "$ffdc_type $ffdc_uc = getFfdcData(FFDC_BUFFER[$objectNumber]);";
            $methods->{$objectNumber}{assignment_string} = "l_obj.$ffdc_uc = $ffdc_uc;";
        }
        else
        {
           # need to use the objectNumber here so when we decode the info at the hwsv/hb side we have a reference,
           # they will be copied into/out of the sbe buffer in the correct order
           $method_body .= "\t{\n\t\tfapi2::g_FfdcData.ffdcData[$objectNumber].data= convertType(i_value);\n";
           $method_body .= "\t\tfapi2::g_FfdcData.ffdcData[$objectNumber].size =";
           $method_body .=" fapi2::getErrorInfoFfdcSize(i_value);\n";
           $method_body .= "\t\tfapi2::g_FfdcData.ffdcLength += sizeof(sbeFfdc_t);\n";
           $method_body .= "\t\treturn *this;\n\t};\n\n";
       }

    }
    elsif ($type eq $buffer_ffdc_type)
    {
        # Two methods - one for integral buffers and one for variable_buffers
        $method =      "\n    template< typename T >\n";
        $method  .=      "    inline $class_name& set_$ffdc_uc(const fapi2::buffer<T>& $param)\n";
        $method_body  =  "    {$ffdc_uc.ptr() = &i_value(); $ffdc_uc.size() = i_value.template getLength<uint8_t>(); return *this;}\n\n";
        $methods->{$key}{member} = "$ffdc_type $ffdc_uc;";
        $methods->{$objectNumber}{localvar} = "$buffer_ffdc_type $ffdc_uc = getFfdcData(FFDC_BUFFER[$objectNumber]);";
        $methods->{$objectNumber}{assignment_string} = "l_obj.$ffdc_uc = $ffdc_uc;";
    }

    elsif ($type eq $variable_buffer_ffdc_type)
    {
        $method       =  "\n    inline $class_name& set_$ffdc_uc(const fapi2::variable_buffer& $param)\n";
        $method_body  =    "    {$ffdc_uc.ptr() = &$param(); $ffdc_uc.size() = $param.template getLength<uint8_t>(); return *this;}\n\n";

        # No need to add the member here, it was added with fapi2::buffer. And we can't have variable
        # buffer support with out integral buffer support (can we?)
    }

    elsif ($type eq $target_ffdc_type)
    {
        $method =      "\n    template< TargetType T >\n";
        $method .=       "    inline $class_name& set_$ffdc_uc(const $type& $param)\n";
        $method_body .=  "    {$ffdc_uc.ptr() = &$param; $ffdc_uc.size() = fapi2::getErrorInfoFfdcSize($param); " .
                              " return *this;}\n\n";

        $methods->{$key}{member} = "$ffdc_type $ffdc_uc;";
        $methods->{$objectNumber}{localvar} = "$ffdc_type $ffdc_uc = getFfdcData(FFDC_BUFFER[$objectNumber]);";
        $methods->{$objectNumber}{assignment_string} = "l_obj.$ffdc_uc=$ffdc_uc";
    }

    else
    {
        $method  .=      "\tinline $class_name& set_$ffdc_uc($type $param)\n";

        if($arg_local_ffdc eq undef)
        {
            $method_body  =  "    { $ffdc_uc = i_value; ";
            $method_body  .= " return *this;}\n\n";
            $methods->{$key}{member} = "$type $ffdc_uc;";
            $methods->{$objectNumber}{localvar} = "$type $ffdc_uc = getFfdcData(FFDC_BUFFER[$objectNumber]);";
            $methods->{$objectNumber}{assignment_string} = "l_obj.$ffdc_uc = $ffdc_uc;";
        }
        else
        {
           # need to use the objectNumber here so when we decode the info at the hwsv/hb side we have a point of
           # reference and they will be copied into/out of the sbe buffer in the correct order
           $method_body .= "\t{\n\t\tfapi2::g_FfdcData.ffdcData[$objectNumber].data= convertType(i_value);\n";
           $method_body .= "\t\tfapi2::g_FfdcData.ffdcData[$objectNumber].size =";
           $method_body .=" fapi2::getErrorInfoFfdcSize(i_value);\n";
           $method_body .= "\t\tfapi2::g_FfdcData.ffdcLength += sizeof(sbeFfdc_t);\n";
           $method_body .= "\t\treturn *this;\n\t};\n\n";
       }
    }

    $method .= ($arg_empty_ffdc eq undef) ? $method_body : "    {return *this;}\n\n";
    $methods->{$key}{method} = $method;
}

#------------------------------------------------------------------------------
# Open output files for writing
#------------------------------------------------------------------------------
my $rcFile = $arg_output_dir;
$rcFile .= "/";
$rcFile .= "hwp_return_codes.H";
open(RCFILE, ">", $rcFile);

my $eiFile = $arg_output_dir;
$eiFile .= "/";
$eiFile .= "hwp_error_info.H";
open(EIFILE, ">", $eiFile);

my $ecFile = $arg_output_dir;
$ecFile .= "/";
$ecFile .= "hwp_ffdc_classes.H";
open(ECFILE, ">", $ecFile);

my $crFile = $arg_output_dir;
$crFile .= "/";
$crFile .= "collect_reg_ffdc_regs.C";
open(CRFILE, ">", $crFile);

my $sbFile = $arg_output_dir;
$sbFile .= "/";
$sbFile .= "set_sbe_error.H";
open(SBFILE, ">", $sbFile);

#------------------------------------------------------------------------------
# Print start of file information to hwp_error_info.H
#------------------------------------------------------------------------------
print EIFILE "// hwp_error_info.H\n";
print EIFILE "// This file is generated by the perl script parseErrorInfo.pl\n\n";
print EIFILE "#ifndef FAPI2_HWPERRORINFO_H_\n";
print EIFILE "#define FAPI2_HWPERRORINFO_H_\n\n";
print EIFILE "#include <target.H>\n";
print EIFILE "#include <plat_trace.H>\n";
print EIFILE "#include <hwp_return_codes.H>\n";
print EIFILE "#include <hwp_executor.H>\n";
print EIFILE "#include <set_sbe_error.H>\n";

print EIFILE "/**\n";
print EIFILE " * \@brief Error Information macros and HwpFfdcId enumeration\n";
print EIFILE " *\/\n";
#------------------------------------------------------------------------------
# Print start of file information to hwp_ffdc_classes.H
#------------------------------------------------------------------------------
print ECFILE "// hwp_ffdc_classes.H\n";
print ECFILE "// This file is generated by the perl script parseErrorInfo.pl\n\n";
print ECFILE "#ifndef FAPI2_HWP_FFDC_CLASSES_H_\n";
print ECFILE "#define FAPI2_HWP_FFDC_CLASSES_H_\n\n";
print ECFILE "#include <return_code.H>\n";
print ECFILE "#include <fapi2_hwp_executor.H>\n";
print ECFILE "#include <error_info.H>\n";
print ECFILE "#include <buffer.H>\n";
print ECFILE "#include <variable_buffer.H>\n" if ($arg_use_variable_buffers ne undef);
print ECFILE "#include <hwp_error_info.H>\n";
print ECFILE "#if !defined(FAPI2_NO_FFDC) && !defined(MINIMUM_FFDC)\n";
print ECFILE "#include <ffdc_includes.H>\n";
print ECFILE "#include <collect_reg_ffdc.H>\n";
print ECFILE "#endif\n";
print ECFILE "/**\n";
print ECFILE " * \@brief FFDC gathering classes\n";
print ECFILE " *\/\n";
print ECFILE "namespace fapi2\n{\n";
if($arg_local_ffdc)
{
    print ECFILE "extern SbeFfdcData_t g_FfdcData; \n";
}
#------------------------------------------------------------------------------
# Print start of file information to collect_reg_ffdc_regs.C
#------------------------------------------------------------------------------
print CRFILE "// collect_reg_ffdc_regs.C\n";
print CRFILE "// This file is generated by the perl script parseErrorInfo.pl\n\n";
print CRFILE "#include <stdint.h>\n";
print CRFILE "#include <vector>\n";
print CRFILE "#include <plat_trace.H>\n";
print CRFILE "#include <hwp_error_info.H>\n";
print CRFILE "#include <p9_mc_scom_addresses.H>\n";
print CRFILE "#include <p9_misc_scom_addresses.H>\n";
print CRFILE "#include <p9_obus_scom_addresses.H>\n";
print CRFILE "#include <p9_perv_scom_addresses.H>\n";
print CRFILE "#include <p9_quad_scom_addresses.H>\n";
print CRFILE "#include <p9_xbus_scom_addresses.H>\n";
print CRFILE "namespace fapi2\n";
print CRFILE "{\n";
print CRFILE "void getAddressData(const fapi2::HwpFfdcId i_ffdcId,\n";
print CRFILE "                        std::vector<uint64_t>& o_scomAddresses ,\n";
print CRFILE "                        std::vector<uint32_t>& o_cfamAddresses ,\n";
print CRFILE "                        uint32_t & o_ffdcSize )\n";
print CRFILE "{\n";
print CRFILE "    FAPI_INF(\"getAddresses. FFDC ID: 0x%x\", i_ffdcId);\n";
print CRFILE "    o_ffdcSize = 0;\n\n";
print CRFILE "    switch (i_ffdcId)\n";
print CRFILE "    {\n";
#------------------------------------------------------------------------------
# Print start of file information to setSbeError.H
#------------------------------------------------------------------------------
print SBFILE "// setSbeError.H\n";
print SBFILE "// This file is generated by the perl script parseErrorInfo.pl\n\n";
print SBFILE "// When SBE code creates an error, it produces an error value\n";
print SBFILE "// that matches a value in the HwpReturnCode enum in\n";
print SBFILE "// fapiHwpReturnCodes.H. The SBE uses the __ASSEMBLER__\n";
print SBFILE "// primitives in hwpReturnCodes.H to do this. The function\n";
print SBFILE "// that extracts the error value from the SBE needs to call\n";
print SBFILE "// FAPI_SET_HWP_ERROR to create the error and get all the\n";
print SBFILE "// actions in the error XML file performed, but that macro can\n";
print SBFILE "// only be called with the enumerator, not the value. This\n";
print SBFILE "// FAPI_SET_SBE_ERROR macro can be called instead, it calls\n";
print SBFILE "// FAPI_SET_HWP_ERROR with the correct error enumerator.\n";
print SBFILE "// Errors containing <sbeError/> in their XML are supported\n";
print SBFILE "// in this macro.\n\n";
print SBFILE "// Note that it is expected that this macro will be called\n";
print SBFILE "// in one place (the function that extracts the error from\n";
print SBFILE "// the SBE), if this changes and it is called in multiple\n";
print SBFILE "// places then the macro could be turned into a function to\n";
print SBFILE "// avoid the code size increase of expanding the macro in\n";
print SBFILE "// multiple places. The function approach is slightly more\n";
print SBFILE "// complicated, there is an extra C file and the function\n";
print SBFILE "// must take a parameter for the generic chip ID in the error\n";
print SBFILE "// XML.\n\n";
print SBFILE "#ifndef FAPI2_SETSBEERROR_H_\n";
print SBFILE "#define FAPI2_SETSBEERROR_H_\n\n";
print SBFILE "#define FAPI_SET_SBE_ERROR(RC,ERRVAL,FFDC_BUFFER)\\\n";
print SBFILE "{\\\n";
print SBFILE "switch (ERRVAL)\\\n";
print SBFILE "{\\\n";


#------------------------------------------------------------------------------
# For each XML file
#------------------------------------------------------------------------------
foreach my $argnum (0 .. $#ARGV)
{
    my $infile = $ARGV[$argnum];
    my $count = 0;

    #--------------------------------------------------------------------------
    # Read XML file. The ForceArray option ensures that there is an array of
    # elements even if there is only one element
    #--------------------------------------------------------------------------
    my $errors = $xml->XMLin($infile, ForceArray =>
        ['hwpError', 'collectFfdc', 'ffdc','mcastId', 'callout', 'deconfigure', 'gard',
         'registerFfdc', 'collectRegisterFfdc', 'cfamRegister', 'scomRegister',
         'id','collectTrace', 'buffer']);

    # Uncomment to get debug output of all errors
#    print "\nFile: ", $infile, "\n", Dumper($errors), "\n";

    #--------------------------------------------------------------------------
    # For each Error
    #--------------------------------------------------------------------------
    foreach my $err (@{$errors->{hwpError}})
    {
        my $objectStr = undef;
        # Hash of methods for the ffdc-gathering class
        my %methods;

        # Array of EI Objects
         @eiObjects = ();

        #----------------------------------------------------------------------
        # Check that expected fields are present
        #----------------------------------------------------------------------
        if (! exists $err->{rc})
        {
            print ("parseErrorInfo.pl ERROR. rc missing\n");
            exit(1);
        }

        if (! exists $err->{description})
        {
            print ("parseErrorInfo.pl ERROR in $err->{rc}. description missing\n");
            exit(1);
        }

        #----------------------------------------------------------------------
        # Check that this rc hasn't been deprecated
        #----------------------------------------------------------------------
        if ($deprecated{$err->{rc}} ne undef)
        {
            print "WARNING: $err->{rc} has been deprecated because $deprecated{$err->{rc}}\n";
            next;
        }

        #----------------------------------------------------------------------
        # Set the error enum value in a global hash
        #---------------------------------------------------------------------
        setErrorEnumValue($err->{rc});


        #----------------------------------------------------------------------
        # Print the CALL_FUNCS_TO_COLLECT_FFDC macro to hwp_error_info.H
        #----------------------------------------------------------------------
        print EIFILE "#define $err->{rc}_CALL_FUNCS_TO_COLLECT_FFDC(RC)";

        my $collectFfdcStr = undef;
        $count = 0;
        foreach my $collectFfdc (@{$err->{collectFfdc}})
        {
            if ($count == 0)
            {
                #this rc wont be used, except to indicate the FFDC collection failed
                $collectFfdcStr =  "\tfapi2::ReturnCode l_rc; \\\n";
                # each collect ffdc function needs to populate this so we can add it to i_rc;
                $collectFfdcStr .= "\tstd::vector<std::shared_ptr<ErrorInfoFfdc>>ffdc; \\\n";
            }
            $count++;

            # collectFfdc is a string we're going to stuff into FAPI_EXEC_HWP
            # but we need to create the arguments in the ffdc class. The first
            # element in the collectFfdc string is the function to call.
            my @elements = split /,/, $collectFfdc;
            my @signature = @{$signatures{@elements[0]}};

            # build up the function call here
            @elements[0] =~ s/^\s+|\s+$//g;
            $collectFfdc =  "@elements[0]" .",ffdc";
            for (my $i = 1; $i <= $#elements; $i++)
            {
                $collectFfdc .= ",";

                # the parameters will be in the l_objects, unused, but need to be
                # counted for the SBE implementation
                my $parameter = "static_cast<void*>(&"."@elements[$i])";

                # Add the parameter to the object list if it doesn't already exist
                #
                my $objNum = addEntryToArray(\@eiObjects, $parameter);

                # add a set method for each parameter too..
                @elements[$i] =~ s/^\s+|\s+$//g;
                addFfdcMethod(\%methods, @elements[$i], $err->{rc}, @signature[$i-1],$objNum);

                $collectFfdc .=  "@elements[$i]"

            }

            $collectFfdcStr .= "\tFAPI_EXEC_HWP(l_rc, $collectFfdc); \\\n";

            print EIFILE "\\\n{ \\\n$collectFfdcStr";
            print EIFILE "\tRC.addErrorInfo(ffdc); \\\n}";
        } #end collectFfdc tag

        print EIFILE "\n";

        #----------------------------------------------------------------------
        # Print the CALL_FUNCS_TO_COLLECT_REG_FFDC macro to hwp_error_info.H
        #----------------------------------------------------------------------
        print EIFILE "#define $err->{rc}_CALL_FUNCS_TO_COLLECT_REG_FFDC(RC)";

        my $crffdcStr = undef;

        my $crffdcCount =0;

        if($arg_local_ffdc eq undef)
        {
            foreach my $collectRegisterFfdc (@{$err->{collectRegisterFfdc}})
            {
                #------------------------------------------------------------------
                # Check that expected fields are present
                #------------------------------------------------------------------
                if (! exists $collectRegisterFfdc->{id}[0])
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. id(s) missing from collectRegisterFfdc $infile\n");
                    exit(1);
                }


                foreach my $id (@{$collectRegisterFfdc->{id}})
                {

                    if( $crffdcCount eq 0 )
                    {
                        print EIFILE " \\\n{ \\\n";
                        $crffdcStr =  "\tstd::vector<std::shared_ptr<ErrorInfoFfdc>> ffdc; \\\n";
                    }
                    else
                    {
                        $crffdcStr = "";
                    }

                    $crffdcCount++;
                    #---------------------------------------------------------------------------------
                    # Check FFDC register collection type: target, child, or based on present children
                    #---------------------------------------------------------------------------------
                    if (exists $collectRegisterFfdc->{target})
                    {
                        if(!(exists $collectRegisterFfdc->{targetType} ))
                        {
                           print ("parseErrorInfo.pl ERROR: target type missing from $collectRegisterFfdc->{target} in file $infile\n");
                           exit(1);
                        }
                        $crffdcStr .=  "\tfapi2::collectRegFfdc<$collectRegisterFfdc->{targetType}>($collectRegisterFfdc->{target},";
                        $crffdcStr .=  "fapi2::$id,ffdc); \\\n";

                        addFfdcMethod(\%methods, $collectRegisterFfdc->{target},
                            $err->{rc}, $target_ffdc_type);
                    }
                    elsif (exists $collectRegisterFfdc->{childTargets})
                    {
                        if(!(exists $collectRegisterFfdc->{childTargets}{parent} ))
                        {
                            print ("parseErrorInfo.pl ERROR:  parent missing from $collectRegisterFfdc->{id} in  $infile\n");
                            exit(1);
                        }

                        if(!(exists $collectRegisterFfdc->{childTargets}{parentType} ))
                        {
                            print ("parseErrorInfo.pl ERROR: parent type missing from $collectRegisterFfdc->{id} in $infile\n");
                            exit(1);
                        }

                        $crffdcStr .= "\tfapi2::collectRegFfdc<fapi2::$collectRegisterFfdc->{childTargets}->{childType},";
                        $crffdcStr .= "$collectRegisterFfdc->{childTargets}->{parentType}>";
                        $crffdcStr .= "($collectRegisterFfdc->{childTargets}->{parent}, ";
                        $crffdcStr .= "fapi2::TARGET_STATE_FUNCTIONAL,fapi2::$id, ffdc); \\\n";

                        addFfdcMethod(\%methods, $collectRegisterFfdc->{childTargets}->{parent},
                            $err->{rc}, $target_ffdc_type);
                    }
                    elsif (exists $collectRegisterFfdc->{basedOnPresentChildren})
                    {
                        if ( exists $collectRegisterFfdc->{basedOnPresentChildren}->{target})
                        {
                            if (! exists $collectRegisterFfdc->{basedOnPresentChildren}->{childType})
                            {
                                die ("parseErrorInfo.pl ERROR: childType missing from collectRegisterFfdc $infile\n");
                                exit(1);
                            }
                            if(!(exists $collectRegisterFfdc->{basedOnPresentChildren}{targetType} ))
                            {
                                print ("parseErrorInfo.pl ERROR:  type missing from ");
                                print ("$collectRegisterFfdc->{basedOnPresentChildren}{parent} in file $infile\n");
                                exit(1);
                            }

                            if (! exists $collectRegisterFfdc->{basedOnPresentChildren}->{childPosOffsetMultiplier})
                            {
                                print ("parseErrorInfo.pl ERROR: childPosOffsetMultiplier missing from collectRegisterFfdc $infile\n");
                                exit(1);
                            }
                            $crffdcStr .= "\tfapi2::collectRegFfdc<fapi2::$collectRegisterFfdc->{basedOnPresentChildren}->{childType},";
                            $crffdcStr .= "$collectRegisterFfdc->{basedOnPresentChildren}->{targetType}>";
                            $crffdcStr .= "($collectRegisterFfdc->{basedOnPresentChildren}->{target},";
                            $crffdcStr .= "fapi2::TARGET_STATE_PRESENT,";
                            $crffdcStr .= "fapi2::$id, ffdc,";
                            $crffdcStr .= "$collectRegisterFfdc->{basedOnPresentChildren}->{childPosOffsetMultiplier});\\\n";
                            $crffdcCount++;

                            addFfdcMethod(\%methods, $collectRegisterFfdc->{basedOnPresentChildren}->{target},
                                $err->{rc}, $target_ffdc_type);
                        }
                        else
                        {
                            print ("parseErrorInfo.pl ERROR: Invalid collectRegisterFfdc configuration in $infile\n");
                            exit(1);

                        }
                    }
                    else
                    {
                        print ("parseErrorInfo.pl ERROR: Invalid collectRegisterFfdc configuration in $infile\n");
                        exit(1);
                    }

                    #print the collectRegFfdc string to the info file
                    print EIFILE "$crffdcStr";

                } #end foreach register id

            } # end foreach collectRegisterFfdc

            if($crffdcCount > 0)
            {
                print EIFILE "\tRC.addErrorInfo(ffdc); \\\n}\n";
            }

        }
        print EIFILE "\n";

        #----------------------------------------------------------------------
        # Print the ADD_ERROR_INFO macro to hwp_error_info.H
        #----------------------------------------------------------------------
        print EIFILE "#define $err->{rc}_ADD_ERROR_INFO(RC)";

        my $eiEntryStr = undef;
        my $eiObjectMap = undef;  #object names to buffer address mapping
        my $eiObjectStr = "\tconst void * l_objects[] = {";
        my $executeStr = undef;
        my $eiEntryCount = 0;
        my %cdgTargetHash; # Records the callout/deconfigure/gards for Targets
        my %cdgChildHash;  # Records the callout/deconfigure/gards for Children

        # collect firmware trace
        foreach my $collectTrace (@{$err->{collectTrace}})
        {
            # Add an EI entry to eiEntryStr
            $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_COLLECT_TRACE; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].collect_trace.iv_eieTraceId =  fapi2::CollectTraces::$collectTrace; \\\n";
            $eiEntryCount++;
        } #end foreach $collectTrace

        # Local FFDC
        foreach my $ffdc (@{$err->{ffdc}})
        {

            # Set the FFDC ID value in a global hash. The name is <rc>_<ffdc>
            my $ffdcName = $err->{rc} . "_";
            $ffdcName = $ffdcName . $ffdc;
            setFfdcIdValue($ffdcName);

            # Add the FFDC data to the EI Object array if it doesn't already exist
            my $objNum = addEntryToArray(\@eiObjects, $ffdc);

            # Add a method to the ffdc-gathering class
            addFfdcMethod(\%methods, $ffdc, $err->{rc},$ffdc_type,$objNum);

            $ffdc = $mangle_names{$ffdc} if ($mangle_names{$ffdc} ne undef);

            # Add an EI entry to eiEntryStr
            $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_FFDC; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcObjIndex = $objNum; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcId = fapi2::$ffdcName; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcSize = $ffdc.size(); \\\n";
            $eiEntryCount++;
        } #end foreach $ffdc

        # Multicast ID
        foreach my $mcast (@{$err->{mcastId}})
        {
            # Set the FFDC ID value in a global hash. The name is <rc>_<ffdc>
            my $ffdcName = $err->{rc} . "_";
            $ffdcName = $ffdcName . $mcast;
            setFfdcIdValue($ffdcName);

            # Add the FFDC data to the EI Object array if it doesn't already exist
            my $objNum = addEntryToArray(\@eiObjects, $mcast);

            # Add a method to the ffdc-gathering class
            addFfdcMethod(\%methods, $mcast, $err->{rc},$mcast_type,$objNum);

            $mcast = $mangle_names{$mcast} if ($mangle_names{$mcast} ne undef);

            # Add an EI entry to eiEntryStr
            $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_FFDC; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcObjIndex = $objNum; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcId = fapi2::$ffdcName; \\\n";
            $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcSize = 4; \\\n";
            $eiEntryCount++;
        } #foreach mcastId

        if($arg_local_ffdc eq undef)
        {
            # Buffers, looks a lot like local ffdc
            foreach my $buffer (@{$err->{buffer}})
            {
                # Set the FFDC ID value in a global hash. The name is <rc>_<ffdc>
                my $bufferName = $err->{rc} . "_";
                $bufferName = $bufferName . $buffer;
                setFfdcIdValue($bufferName);

                # Add the FFDC data to the EI Object array if it doesn't already exist
                my $objNum = addEntryToArray(\@eiObjects, $buffer);

                # Add a method to the ffdc-gathering class - one for each buffer type
                addFfdcMethod(\%methods, $buffer, $err->{rc}, $buffer_ffdc_type);
                addFfdcMethod(\%methods, $buffer, $err->{rc}, $variable_buffer_ffdc_type);

                # Add an EI entry to eiEntryStr
                $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_FFDC; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcObjIndex = $objNum; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcId = fapi2::$bufferName; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].ffdc.iv_ffdcSize = fapi2::getErrorInfoFfdcSize($buffer); \\\n";
                $eiEntryCount++;
            } #foreach $buffer

            # Procedure/Target/Bus/Child callouts
            foreach my $callout (@{$err->{callout}})
            {
                if (! exists $callout->{priority})
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. Callout priority missing\n");
                    exit(1);
                }

                my $elementsFound = 0;
                if (exists $callout->{hw})
                {
                    # HW Callout
                    if (! exists $callout->{hw}->{hwid})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. HW Callout hwid missing\n");
                        exit(1);
                    }

                    # Check that those HW callouts that need reference targets have them
                    if (($callout->{hw}->{hwid} eq "TOD_CLOCK") ||
                        ($callout->{hw}->{hwid} eq "MEM_REF_CLOCK") ||
                        ($callout->{hw}->{hwid} eq "PROC_REF_CLOCK") ||
                        ($callout->{hw}->{hwid} eq "PCI_REF_CLOCK"))
                    {
                        if (! exists $callout->{hw}->{refTarget})
                        {
                            print ("parseErrorInfo.pl ERROR in $err->{rc}. Callout missing refTarget\n");
                            exit(1);
                        }
                    }

                    # Add an EI entry to eiEntryStr
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_HW_CALLOUT; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].hw_callout.iv_hw = fapi2::HwCallouts::$callout->{hw}->{hwid}; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].hw_callout.iv_calloutPriority = fapi2::CalloutPriorities::$callout->{priority}; \\\n";
                    if (exists $callout->{hw}->{refTarget})
                    {
                        # Add the Targets to the objectlist if they don't already exist
                        my $objNum = addEntryToArray(\@eiObjects, $callout->{hw}->{refTarget});
                        $eiEntryStr .= "\tl_entries[$eiEntryCount].hw_callout.iv_refObjIndex = $objNum; \\\n";

                        # Add a method to the ffdc-gathering class
                        addFfdcMethod(\%methods, $callout->{hw}->{refTarget}, $err->{rc});
                    }
                    else
                    {
                        $eiEntryStr .= "\tl_entries[$eiEntryCount].hw_callout.iv_refObjIndex = 0xff; \\\n";
                    }
                    $eiEntryCount++;
                    $elementsFound++;
                }
                if (exists $callout->{procedure})
                {
                    # Procedure Callout
                    # Add an EI entry to eiEntryStr
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_PROCEDURE_CALLOUT; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].proc_callout.iv_procedure = fapi2::ProcedureCallouts::$callout->{procedure}; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].proc_callout.iv_calloutPriority = fapi2::CalloutPriorities::$callout->{priority}; \\\n";
                    $eiEntryCount++;
                    $elementsFound++;
                }
                if (exists $callout->{bus})
                {
                    # A Bus Callout consists of two targets separated by
                    # commas/spaces
                    my @targets = split(/\s*,\s*|\s+/, $callout->{bus});

                    if (scalar @targets != 2)
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. did not find two targets in bus callout\n");
                        exit(1);
                    }

                    # Add the Targets to the objectlist if they don't already exist
                    my $objNum1 = addEntryToArray(\@eiObjects, $targets[0]);

                    my $objNum2 = addEntryToArray(\@eiObjects, $targets[1]);

                    # Add a method to the ffdc-gathering class
                    addFfdcMethod(\%methods, $targets[0], $err->{rc}, $target_ffdc_type);
                    addFfdcMethod(\%methods, $targets[1], $err->{rc}, $target_ffdc_type);

                    # Add an EI entry to eiEntryStr
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_BUS_CALLOUT; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].bus_callout.iv_endpoint1ObjIndex = $objNum1; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].bus_callout.iv_endpoint2ObjIndex = $objNum2; \\\n";
                    $eiEntryStr .= "\tl_entries[$eiEntryCount].bus_callout.iv_calloutPriority = fapi2::CalloutPriorities::$callout->{priority}; \\\n";
                    $eiEntryCount++;
                    $elementsFound++;
                }
                if (exists $callout->{target})
                {
                    # Add the Target to cdgTargetHash to be processed with any
                    # deconfigure and GARD requests
                    $cdgTargetHash{$callout->{target}}{callout} = 1;
                    $cdgTargetHash{$callout->{target}}{priority} =
                    $callout->{priority};

                    $elementsFound++;
                }
                if (exists $callout->{childTargets})
                {
                    # Check that the parent and childType subelements exist
                    if (! exists $callout->{childTargets}->{parent})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. Child Callout parent missing\n");
                        exit(1);
                    }

                    if (! exists $callout->{childTargets}->{childType})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. Child Callout childType missing\n");
                        exit(1);
                    }

                    # Add the child info to cdgChildHash to be processed with
                    # any deconfigure and GARD requests
                    my $parent = $callout->{childTargets}->{parent};
                    my $childType = $callout->{childTargets}->{childType};
                    $cdgChildHash{$parent}{$childType}{callout} = 1;
                    $cdgChildHash{$parent}{$childType}{priority} =
                    $callout->{priority};

                    $elementsFound++;

                    if (exists $callout->{childTargets}->{childPort})
                    {
                        my $childPort = $callout->{childTargets}->{childPort};

                        $cdgChildHash{$parent}{$childType}{childPort} = $childPort;
                    }

                    if (exists $callout->{childTargets}->{childNumber})
                    {
                        my $childNum = $callout->{childTargets}->{childNumber};
                        $cdgChildHash{$parent}{$childType}{childNumber} = $childNum;
                    }

                }
                if ($elementsFound == 0)
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. Callout incomplete\n");
                    exit(1);
                }
                elsif ($elementsFound > 1)
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. Callout has multiple elements\n");
                    exit(1);
                }
            } # callout

            # Target/Child deconfigures
            foreach my $deconfigure (@{$err->{deconfigure}})
            {
                my $elementsFound = 0;
                if (exists $deconfigure->{target})
                {
                    # Add the Target to cdgTargetHash to be processed with any
                    # callout and GARD requests
                    $cdgTargetHash{$deconfigure->{target}}{deconf} = 1;
                    $elementsFound++;
                }
                if (exists $deconfigure->{childTargets})
                {
                    # Check that the parent and childType subelements exist
                    if (! exists $deconfigure->{childTargets}->{parent})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. Child Deconfigure parent missing\n");
                        exit(1);
                    }
                    if (! exists $deconfigure->{childTargets}->{childType})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. Child Deconfigure childType missing\n");
                        exit(1);
                    }

                    # Add the child info to cdgChildHash to be processed with
                    # any callout and GARD requests
                    my $parent = $deconfigure->{childTargets}->{parent};
                    my $childType = $deconfigure->{childTargets}->{childType};
                    $cdgChildHash{$parent}{$childType}{deconf} = 1;

                    $elementsFound++;

                    if ( exists $deconfigure->{childTargets}->{childPort})
                    {
                        my $childPort = $deconfigure->{childTargets}->{childPort};

                        $cdgChildHash{$parent}{$childType}{childPort} = $childPort;
                    }

                    if ( exists $deconfigure->{childTargets}->{childNumber})
                    {
                        my $childNum = $deconfigure->{childTargets}->{childNumber};
                        $cdgChildHash{$parent}{$childType}{childNumber} = $childNum;

                    }
                }
                if ($elementsFound == 0)
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. Deconfigure incomplete\n");
                    exit(1);
                }
                elsif ($elementsFound > 1)
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. Deconfigure has multiple elements\n");
                    exit(1);
                }
            } # deconfigure

            # Target/Child Gards
            foreach my $gard (@{$err->{gard}})
            {
                my $elementsFound = 0;
                if (exists $gard->{target})
                {
                    # Add the Target to cdgTargetHash to be processed with any
                    # callout and deconfigure requests
                    $cdgTargetHash{$gard->{target}}{gard} = 1;
                    $elementsFound++;
                }
                if (exists $gard->{childTargets})
                {
                    # Check that the parent and childType subelements exist
                    if (! exists $gard->{childTargets}->{parent})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. Child GARD parent missing\n");
                        exit(1);
                    }
                    if (! exists $gard->{childTargets}->{childType})
                    {
                        print ("parseErrorInfo.pl ERROR in $err->{rc}. Child GARD childType missing\n");
                        exit(1);
                    }

                    # Add the child info to cdgChildHash to be processed with
                    # any callout and deconfigure requests
                    my $parent = $gard->{childTargets}->{parent};
                    my $childType = $gard->{childTargets}->{childType};
                    $cdgChildHash{$parent}{$childType}{gard} = 1;

                    $elementsFound++;

                    if ( exists $gard->{childTargets}->{childPort})
                    {
                        my $childPort = $gard->{childTargets}->{childPort};

                        $cdgChildHash{$parent}{$childType}{childPort} = $childPort;

                    }

                    if ( exists $gard->{childTargets}->{childNumber})
                    {
                        my $childNum = $gard->{childTargets}->{childNumber};
                        $cdgChildHash{$parent}{$childType}{childNumber} = $childNum;
                    }
                }
                if ($elementsFound == 0)
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. GARD incomplete\n");
                    exit(1);
                }
                elsif ($elementsFound > 1)
                {
                    print ("parseErrorInfo.pl ERROR in $err->{rc}. GARD has multiple elements\n");
                    exit(1);
                }
            } # gard

            # Process the callout, deconfigures and GARDs for each Target
            foreach my $cdg (keys %cdgTargetHash)
            {
                my $callout = 0;
                my $priority = 'LOW';
                my $deconf = 0;
                my $gard = 0;

                if (exists $cdgTargetHash{$cdg}->{callout})
                {
                    $callout = 1;
                }
                if (exists $cdgTargetHash{$cdg}->{priority})
                {
                    $priority = $cdgTargetHash{$cdg}->{priority};
                }
                if (exists $cdgTargetHash{$cdg}->{deconf})
                {
                    $deconf = 1;
                }
                if (exists $cdgTargetHash{$cdg}->{gard})
                {
                    $gard = 1;
                }

                # Add the Target to the objectlist if it doesn't already exist
                my $objNum = addEntryToArray(\@eiObjects, $cdg);

                # Add a method to the ffdc-gathering class
                addFfdcMethod(\%methods, $cdg, $err->{rc}, $target_ffdc_type);

                # Add an EI entry to eiEntryStr
                $eiEntryStr .= "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_CDG; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].target_cdg.iv_targetObjIndex = $objNum; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].target_cdg.iv_callout = $callout; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].target_cdg.iv_deconfigure = $deconf; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].target_cdg.iv_gard = $gard; \\\n";
                $eiEntryStr .= "\tl_entries[$eiEntryCount].target_cdg.iv_calloutPriority = fapi2::CalloutPriorities::$priority; \\\n";
                $eiEntryCount++;
            }

            # Process the callout, deconfigures and GARDs for Child Targets
            foreach my $parent (keys %cdgChildHash)
            {
                foreach my $childType (keys %{$cdgChildHash{$parent}})
                {
                    my $callout = 0;
                    my $priority = 'LOW';
                    my $deconf = 0;
                    my $gard = 0;
                    my $childPort = 0xFF;
                    my $childNumber = 0xFF;

                    if (exists $cdgChildHash{$parent}{$childType}->{callout})
                    {
                        $callout = 1;
                    }
                    if (exists $cdgChildHash{$parent}->{$childType}->{priority})
                    {
                        $priority =
                        $cdgChildHash{$parent}->{$childType}->{priority};
                    }
                    if (exists $cdgChildHash{$parent}->{$childType}->{deconf})
                    {
                        $deconf = 1;
                    }
                    if (exists $cdgChildHash{$parent}->{$childType}->{childPort})
                    {
                        $childPort =
                        $cdgChildHash{$parent}->{$childType}->{childPort} ;
                        addFfdcMethod(\%methods, $childPort, $err->{rc});
                    }
                    if (exists $cdgChildHash{$parent}->{$childType}->{childNumber})
                    {
                        $childNumber =
                        $cdgChildHash{$parent}->{$childType}->{childNumber} ;
                        addFfdcMethod(\%methods, $childNumber, $err->{rc});
                    }
                    if (exists $cdgChildHash{$parent}->{$childType}->{gard})
                    {
                        $gard = 1;
                    }


                    # Add the Target to the objectlist if it doesn't already exist
                    my $objNum = addEntryToArray(\@eiObjects, $parent);
                    addFfdcMethod(\%methods, $parent, $err->{rc}, $target_ffdc_type);

                    # Add an EI entry to eiEntryStr
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].iv_type = fapi2::EI_TYPE_CHILDREN_CDG; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_parentObjIndex = $objNum; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_callout = $callout; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_deconfigure = $deconf; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_childType = fapi2::$childType; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_childPort = $childPort; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_childNumber = $childNumber; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_gard = $gard; \\\n";
                    $eiEntryStr .=
                    "\tl_entries[$eiEntryCount].children_cdg.iv_calloutPriority = fapi2::CalloutPriorities::$priority; \\\n";
                    $eiEntryCount++;
                }
            }
        }
        # Add all objects to $eiObjectStr
        my $objCount = 0;

        # add ordinary types to eiObjectStr here

        foreach my $eiObject (@eiObjects)
        {
            if ($objCount > 0)
            {
                $eiObjectStr .= ", ";
            }

            if ($mangle_names{$eiObject} eq undef)
            {
                $eiObjectStr .= "$eiObject";

                if ((exists $err->{sbeError}) )
                {
                   if((exists $methods{$objCount}{object}))
                    {
                        $objectStr .= "\t\t$methods{$objCount}{object} \\\n";

                    }

                   if((exists $methods{$objCount}{localvar}))
                    {
                        $objectStr .= "\t\t$methods{$objCount}{localvar} \\\n";
                        $objectStr .= "\t\t$methods{$objCount}{assignment_string} \\\n";
                    }
                }
            }
            else
            {
                $eiObjectStr .= $mangle_names{$eiObject};
            }

            $objCount++;
        }


        $eiObjectStr .= "};";


        # Print info to file
        if ($eiEntryCount > 0)
        {
            print EIFILE " \\\n{ \\\n $eiObjectStr \\\n";
            print EIFILE "\tfapi2::ErrorInfoEntry l_entries[$eiEntryCount]; \\\n";
            print EIFILE "$eiEntryStr";
            print EIFILE "\tRC.addErrorInfo(l_objects, l_entries, $eiEntryCount); \\\n}";
        }

        print EIFILE "\n";

        #----------------------------------------------------------------------
        # Print the return code class to hwp_error_info.H
        #----------------------------------------------------------------------
        # Remove the repeated whitespace and newlines other characters from the description
        $err->{description} =~ s/^\s+|\s+$|"//g;
        $err->{description} =~ tr{\n}{ };
        $err->{description} =~ s/\h+/ /g;

        #----------------------------------------------------------------------
        # Print the return code class to hwp_error_info.H
        #----------------------------------------------------------------------
        my $class_name = $err->{rc};
        # Remove everything upto and including the first _. This makes the ffdc class
        # names different from the error code value enum names.
        $class_name = (split (/_/, $class_name, 2))[1];

        # Class declaration
        print ECFILE "\nclass $class_name\n{\n  public:\n";

        # Constructor. This traces the description. If this is too much, we can
        # remove it.
        if ($arg_empty_ffdc eq undef)
        {
            if($arg_local_ffdc eq undef)
            {
                print ECFILE "    $class_name(fapi2::errlSeverity_t i_sev = fapi2::FAPI2_ERRL_SEV_UNRECOVERABLE, fapi2::ReturnCode& i_rc = fapi2::current_err):\n";
                print ECFILE "        iv_rc(i_rc),\n";
                print ECFILE "        iv_sev(i_sev)\n";
                print ECFILE "        { FAPI_ERR(\"$err->{description}\"); }\n\n";
            }
            else
            {
                print ECFILE "    $class_name()\n";
                print ECFILE "    {\n\t\tfapi2::current_err = RC_$class_name;\n\t\tFAPI_ERR(\"$err->{description}\");\n";
                print ECFILE "    \tfapi2::g_FfdcData.fapiRc = RC_$class_name;\n\t}\n\n";
            }
        }
        else
        {
            # Void expression keeps the compiler from complaining about the unused arguments.
            # We want to set the i_rc to the RC if we're empty. This otherwise gets done in _setHwpError()
            print ECFILE "    $class_name(fapi2::errlSeverity_t i_sev = fapi2::FAPI2_ERRL_SEV_UNRECOVERABLE, fapi2::ReturnCode& i_rc = fapi2::current_err)\n";
            print ECFILE "    {\n";
            print ECFILE "        static_cast<void>(i_sev);\n";
            print ECFILE "        i_rc = $err->{rc};\n";
            print ECFILE "    }\n\n";
        }

        my $method_count = 0;
        # Methods
        foreach my $key (keys %methods)
        {
            print ECFILE $methods{$key}{method};
            $method_count++;
        }
        if($arg_local_ffdc eq undef)
        {
            # add a method to adjust the severity if desired
            print ECFILE "\tinline void setSev(const fapi2::errlSeverity_t i_sev)\n";
            if ($arg_empty_ffdc eq undef)
            {
                print ECFILE "\t\t\t{ iv_sev = i_sev;};\n\n";
            }
            else
            {
                print ECFILE "\t\t\t{ static_cast<void>(i_sev);};\n\n";
            }

            # add a method to read the severity if desired
            print ECFILE "\tinline fapi2::errlSeverity_t getSev() const\n";
            if ($arg_empty_ffdc eq undef)
            {
                print ECFILE "\t\t\t{ return iv_sev; };\n\n";
            }
            else
            {
                print ECFILE "\t\t\t{ return fapi2::FAPI2_ERRL_SEV_UNDEFINED; };\n\n";
            }

        }

        if( $arg_local_ffdc eq undef )
        {



            # Stick the execute method at the end of the other methods. We allow
            # passing in of the severity so that macros which call execute() can over-ride
            # the default severity.
            print ECFILE "\tvoid execute(fapi2::errlSeverity_t " .
            "i_sev = fapi2::FAPI2_ERRL_SEV_UNDEFINED," .
            "bool commit = false )\n";
            if ($arg_empty_ffdc eq undef )
            {
                print ECFILE "\t\t{\n";
                print ECFILE "\t\t\tFAPI_SET_HWP_ERROR(iv_rc,$err->{rc});\n\n";
                print ECFILE "\t\t\tif( commit )\n";
                print ECFILE "\t\t\t{\n";
                print ECFILE "\t\t\t\tfapi2::logError(iv_rc, " .
                "(i_sev == fapi2::FAPI2_ERRL_SEV_UNDEFINED)" .
                " ? iv_sev : i_sev);\n";
                print ECFILE "\t\t\t}\n";
                print ECFILE "\t\t}\n";

            }
            else
            {
                print ECFILE "    {\n";
                print ECFILE "        static_cast<void>(i_sev);\n";
                print ECFILE "        static_cast<void>(commit);\n";
                print ECFILE "    }\n\n";
            }

            # Instance variables
            if ($arg_empty_ffdc eq undef)
            {
                print ECFILE "\tpublic:\n";
                foreach my $key (keys %methods)
                {
                    if( !($methods{$key}{member} eq undef) )
                    {
                        print ECFILE "\t\t$methods{$key}{member}\n";
                    }

                }

                print ECFILE "\t\tfapi2::ReturnCode& iv_rc;\n";
                print ECFILE "\t\tfapi2::errlSeverity_t iv_sev;\n";
            }

        }
        else
        {
            print ECFILE "    void execute()\n";
            print ECFILE "    {\n";
            print ECFILE "$executeStr\n";
            print ECFILE "    }\n";
        }

        print ECFILE "};\n\n";

        #----------------------------------------------------------------------
        # If this is an SBE error, add it to set_sbe_error.H
        #----------------------------------------------------------------------
        if (exists $err->{sbeError})
        {
            print SBFILE "\tcase fapi2::$err->{rc}: \\\n";
            print SBFILE "\t{\\\n\t\t$class_name l_obj(";
            print SBFILE "fapi2::FAPI2_ERRL_SEV_UNRECOVERABLE,RC);\\\n";

            if(!($objectStr eq undef ))
            {
                print SBFILE "$objectStr";
            }
            print SBFILE "\t\tl_obj.execute(); \\\n";
            print SBFILE "\t\tbreak; \\\n\t} \\\n";
        }

    } #for each hwpError tag
    #
    #--------------------------------------------------------------------------
    # For each registerFfdc.
    #--------------------------------------------------------------------------
    foreach my $registerFfdc (@{$errors->{registerFfdc}})
    {
        #----------------------------------------------------------------------
        # Check that expected fields are present
        #----------------------------------------------------------------------
        if (! exists $registerFfdc->{id}[0])
        {
            print ("parseErrorInfo.pl ERROR. id missing from registerFfdc\n");
            exit(1);
        }

        if (scalar @{$registerFfdc->{id}} > 1)
        {
            print ("parseErrorInfo.pl ERROR. multiple ids in registerFfdc\n");
            exit(1);
        }

        #----------------------------------------------------------------------
        # Set the FFDC ID value in a global hash
        #----------------------------------------------------------------------
        setFfdcIdValue($registerFfdc->{id}[0]);

        #----------------------------------------------------------------------
        # Generate code to capture the registers in collect_reg_ffdc_regs.C
        #----------------------------------------------------------------------
        print CRFILE "        case $registerFfdc->{id}[0]:\n";

        # Look for CFAM Register addresses
        foreach my $cfamRegister (@{$registerFfdc->{cfamRegister}})
        {
            print CRFILE "            o_cfamAddresses.push_back($cfamRegister);\n";
        }

        # Look for SCOM Register addresses
        foreach my $scomRegister (@{$registerFfdc->{scomRegister}})
        {
            print CRFILE "            o_scomAddresses.push_back($scomRegister);\n";
        }

        print CRFILE "            break;\n";
    }


}

#------------------------------------------------------------------------------
# Print end of file information to collect_reg_ffdc_regs.C
#------------------------------------------------------------------------------
print CRFILE "        default:\n";
print CRFILE "            FAPI_ERR(\"collect_reg_ffdc_regs.C: Invalid FFDC ID 0x%x\", ";
print CRFILE                     "i_ffdcId);\n";
print CRFILE "            return;\n";
print CRFILE "    }\n";
print CRFILE "o_ffdcSize = o_scomAddresses.size() * sizeof(uint64_t);\n";
print CRFILE "o_ffdcSize += o_cfamAddresses.size() * sizeof(uint32_t);\n";
print CRFILE "}\n";
print CRFILE "} // end namespace\n\n";

#------------------------------------------------------------------------------
# Print the fapiHwpReturnCodes.H file
#------------------------------------------------------------------------------
print RCFILE "// fapiHwpReturnCodes.H\n";
print RCFILE "// This file is generated by perl script parseErrorInfo.pl\n\n";
print RCFILE "#ifndef FAPI2_HWPRETURNCODES_H_\n";
print RCFILE "#define FAPI2_HWPRETURNCODES_H_\n\n";
print RCFILE "#ifndef __ASSEMBLER__\n";
print RCFILE "namespace fapi2\n";
print RCFILE "{\n\n";
print RCFILE "/**\n";
print RCFILE " * \@brief Enumeration of HWP return codes\n";
print RCFILE " *\/\n";
print RCFILE "enum HwpReturnCode\n";
print RCFILE "{\n";
foreach my $key (keys %errNameToValueHash)
{
    print RCFILE "    $key = 0x$errNameToValueHash{$key},\n";
}
print RCFILE "};\n\n";
print RCFILE "}\n\n";
print RCFILE "#else\n";
foreach my $key (keys %errNameToValueHash)
{
    print RCFILE "    .set $key, 0x$errNameToValueHash{$key}\n";
}
print RCFILE "#endif\n";
print RCFILE "#endif\n";

#------------------------------------------------------------------------------
# Print the HwpFfdcId enumeration to hwp_error_info.H
#------------------------------------------------------------------------------
print EIFILE "namespace fapi2\n";
print EIFILE "{\n\n";
if($arg_local_ffdc)
{
    print EIFILE "  extern SbeFfdcData_t g_FfdcData;\n";
}
print EIFILE "/**\n";
print EIFILE " * \@brief Enumeration of FFDC identifiers\n";
print EIFILE " *\/\n";
print EIFILE "enum HwpFfdcId\n";
print EIFILE "{\n";
foreach my $key (keys %ffdcNameToValueHash)
{
    print EIFILE "    $key = 0x$ffdcNameToValueHash{$key},\n";
}
print EIFILE "};\n\n";
print EIFILE "}\n\n";

#------------------------------------------------------------------------------
# Print end of file information to hwp_error_info.H
#------------------------------------------------------------------------------
print EIFILE "\n\n#endif\n";

#------------------------------------------------------------------------------
# Print end of file information to hwp_ffdc_classes.H
#------------------------------------------------------------------------------
print ECFILE "\n};\n"; # close the namespace
print ECFILE "\n\n#endif\n";

#------------------------------------------------------------------------------
# Print end of file information to set_sbe_error.H
#------------------------------------------------------------------------------
print SBFILE "    default:\\\n";
#print SBFILE "        FAPI_SET_HWP_ERROR(RC, RC_SBE_UNKNOWN_ERROR,0);\\\n";
print SBFILE "        break;\\\n";
print SBFILE "}\\\n";
print SBFILE "}\n\n";
print SBFILE "#endif\n";

#------------------------------------------------------------------------------
# Close output files
#------------------------------------------------------------------------------
close(RCFILE);
close(EIFILE);
close(ECFILE);
close(CRFILE);
close(SBFILE);