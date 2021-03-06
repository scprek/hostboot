/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/include/usr/isteps/istep_reasoncodes.H $                  */
/*                                                                        */
/* OpenPOWER HostBoot Project                                             */
/*                                                                        */
/* Contributors Listed Below - COPYRIGHT 2015,2017                        */
/* [+] International Business Machines Corp.                              */
/*                                                                        */
/*                                                                        */
/* Licensed under the Apache License, Version 2.0 (the "License");        */
/* you may not use this file except in compliance with the License.       */
/* You may obtain a copy of the License at                                */
/*                                                                        */
/*     http://www.apache.org/licenses/LICENSE-2.0                         */
/*                                                                        */
/* Unless required by applicable law or agreed to in writing, software    */
/* distributed under the License is distributed on an "AS IS" BASIS,      */
/* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or        */
/* implied. See the License for the specific language governing           */
/* permissions and limitations under the License.                         */
/*                                                                        */
/* IBM_PROLOG_END_TAG                                                     */
#ifndef _ISTEP_REASONCODES_H_
#define _ISTEP_REASONCODES_H_

#include <hbotcompid.H>
namespace ISTEP
{
    /**
     * @brief Defines the ISTEP error log module IDs
     */
    enum istepModuleId
    {
        MOD_INVALID_MODULE                                = 0x00,
        MOD_REPORTING_ERROR                               = 0x01,
        MOD_START_PAYLOAD_CALL_SHUTDOWN                   = 0x02,
        MOD_HOST_ACTIVATE_SLAVE_CORES                     = 0x03,
        MOD_BUILD_HCODE_IMAGES                            = 0x04,
        MOD_PROC_SET_PORE_BAR                             = 0x05,
        MOD_HOST_ACTIVATE_MASTER                          = 0x06,
        MOD_SBE_CENTAUR_INIT                              = 0x07,
        MOD_ENABLE_CORE_CHECKSTOPS                        = 0x08,
        MOD_DECONFIG_PHBS_BASED_ON_PCI_STATE              = 0x09,
        MOD_COMPUTE_PCIE_CONFIG_ATTRS                     = 0x0A,
        MOD_EXIT_CACHE_CONTAINED                          = 0x0B,
        MOD_HOST_GARD                                     = 0x0C,
        MOD_EDI_EI_IO_RUN_TRAINING                        = 0x0D,
        MOD_LOAD_PAYLOAD                                  = 0x0E,
        MOD_GET_CACHE_DECONFIG                            = 0x0F,
        MOD_THREAD_ACTIVATE                               = 0x10,
        MOD_CHECK_SLAVE_SBE_SEEPROM_COMPLETE              = 0x11,
        MOD_PM_LOAD_HOST_DATA_TO_SRAM                     = 0x12,
        MOD_VOLTAGE_CONFIG                                = 0x13,
        MOD_PM_VERIFY_OCC_CHKPT                           = 0x14,
        MOD_UPDATE_REDUNDANT_TPM                          = 0x15,
        MOD_PROC_EXIT_CACHE_CONTAINED                     = 0x16,
        MOD_SBE_PERFORM_UPDATE_CHECK                      = 0x1A,
        MOD_SET_IPL_PARMS                                 = 0x1D,
        MOD_OCC_XSTOP_HANDLER                             = 0x1E,
        MOD_VERIFY_AND_MOVE_PAYLOAD                       = 0x1F,
    };

    /**
     * @brief Defines the ISTEP error log reason codes
     */
    enum istepReasonCode
    {
        RC_NO_MIRRORED_MEMORY                    = ISTEP_COMP_ID | 0x00,
        RC_MM_EXTEND_FAILED                      = ISTEP_COMP_ID | 0x01,
        RC_INVALID_REASONCODE                    = ISTEP_COMP_ID | 0x02,
        RC_FAILURE                               = ISTEP_COMP_ID | 0x03,
        RC_TARGET_NULL                           = ISTEP_COMP_ID | 0x04,
        RC_BAD_RC                                = ISTEP_COMP_ID | 0x05,
        RC_FAIL_MASTER_WINKLE                    = ISTEP_COMP_ID | 0x06,
        RC_MM_UNMAP_ERR                          = ISTEP_COMP_ID | 0x07,
        RC_LOAD_HCODE_FROM_PNOR_FAILED           = ISTEP_COMP_ID | 0x08,
        RC_REPAIR_LOADER_RETRY_OCCURED           = ISTEP_COMP_ID | 0x09,
        RC_MM_MAP_ERR                            = ISTEP_COMP_ID | 0x0A,
        RC_INCORRECT_TARGET_COUNT                = ISTEP_COMP_ID | 0x0B,
        RC_INVALID_TARGET_TYPE                   = ISTEP_COMP_ID | 0x0C,
        RC_INVALID_ATTR_VALUE                    = ISTEP_COMP_ID | 0x0D,
        RC_INVALID_CONFIGURATION                 = ISTEP_COMP_ID | 0x0E,
        RC_INVALID_PCIE_IOP_LANE_CONFIG          = ISTEP_COMP_ID | 0x0F,
        RC_MASTER_CORE_NULL                      = ISTEP_COMP_ID | 0x10,
        RC_MIXED_PBUS_CONNECTION                 = ISTEP_COMP_ID | 0x11,
        RC_SAME_CHIP_PBUS_CONNECTION             = ISTEP_COMP_ID | 0x12,
        RC_CONFLICT_PBUS_CONNECTION              = ISTEP_COMP_ID | 0x13,
        RC_INVALID_RECORD                        = ISTEP_COMP_ID | 0x14,
        RC_INCORRECT_KEWORD_SIZE                 = ISTEP_COMP_ID | 0x15,
        RC_NO_MASTER_CORE_TARGET                 = ISTEP_COMP_ID | 0x16,
        RC_ECMD_INSERT_FAILED                    = ISTEP_COMP_ID | 0x18,
        RC_NO_FUNCTIONAL_PROCS                   = ISTEP_COMP_ID | 0x19,
        RC_NO_PRESENT_EQS                        = ISTEP_COMP_ID | 0x1A,
        RC_NOMINAL_FREQ_MISMATCH                 = ISTEP_COMP_ID | 0x1B,
        RC_PM_OCC_CHKPT_TIMEOUT                  = ISTEP_COMP_ID | 0x1C,
        RC_UPDATE_SECURITY_CTRL_HWP_FAIL         = ISTEP_COMP_ID | 0x1D,
        RC_NO_FUNCTIONAL_MEMORY                  = ISTEP_COMP_ID | 0x1E,
        RC_NO_FUSED_CORE_TARGET                  = ISTEP_COMP_ID | 0x1F,
        RC_POWER_MODE_MISMATCH                   = ISTEP_COMP_ID | 0x20,
        RC_MASTER_PROC_SBE_KEYS_HASH_MISMATCH    = ISTEP_COMP_ID | 0x21,
        RC_MASTER_PROC_PRIMARY_HASH_READ_FAIL    = ISTEP_COMP_ID | 0x22,
        RC_MASTER_PROC_BACKUP_HASH_READ_FAIL     = ISTEP_COMP_ID | 0x23,
        RC_MASTER_PROC_CBS_CONTROL_READ_FAIL     = ISTEP_COMP_ID | 0x24,
        RC_SLAVE_PROC_PRIMARY_HASH_READ_FAIL     = ISTEP_COMP_ID | 0x25,
        RC_SLAVE_PROC_BACKUP_HASH_READ_FAIL      = ISTEP_COMP_ID | 0x26,
        RC_SLAVE_PROC_CBS_CONTROL_READ_FAIL      = ISTEP_COMP_ID | 0x27,
        RC_PROC_SECURITY_STATE_MISMATCH          = ISTEP_COMP_ID | 0x28,
        RC_MIN_HW_CHECK_FAILED                   = ISTEP_COMP_ID | 0x29,
        RC_PROC_EXTRACT_SBE_MAIN_ERROR           = ISTEP_COMP_ID | 0x30,
        RC_SBE_UPDATE_IN_MPIPL                   = ISTEP_COMP_ID | 0x32,
        RC_NO_FFDC_RETURNED                      = ISTEP_COMP_ID | 0x33,
        RC_P9N_DD1_NOT_SUPPORTED                 = ISTEP_COMP_ID | 0x35,
        RC_PREVENT_REBOOT_IN_MFG_TERM_MODE       = ISTEP_COMP_ID | 0x36,
        RC_FAILED_WRITE_SPR                      = ISTEP_COMP_ID | 0x37,
    };

};

#endif
