/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/import/chips/p9/procedures/hwp/pm/p9_pm_recovery_ffdc_sgpe.C $ */
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
// *INDENT-OFF*


///
/// @file   p9_pm_recovery_ffdc_sgpe.C
/// @brief  Models SGPE platform for the FFDC collection of PM complex
///
/// *HWP HWP Owner:      Greg Still <stillgs@us.ibm.com>
/// *HWP FW Owner:       Prem S Jha <premjha2@in.ibm.com>
/// *HWP Team:           PM
/// *HWP Level:          2
/// *HWP Consumed by:    Hostboot
//
// *INDENT-OFF*
//--------------------------------------------------------------------------
// Includes
//--------------------------------------------------------------------------

#include <p9_pm_recovery_ffdc_sgpe.H>
#include <p9_hcd_memmap_occ_sram.H>
#include <p9_ppe_defs.H>
#include <stddef.h>
#include <endian.h>

 namespace p9_stop_recov_ffdc
 {
    PlatSgpe::PlatSgpe( const fapi2::Target< fapi2::TARGET_TYPE_PROC_CHIP > i_procChipTgt )
      : PlatPmComplex( i_procChipTgt,
                       PLAT_SGPE,
                       OCC_SRAM_SGPE_HEADER_ADDR,
                       OCC_SRAM_SGPE_TRACE_START,
                       OCC_SRAM_SGPE_DASHBOARD_START )
    { }

//----------------------------------------------------------------------

    fapi2::ReturnCode PlatSgpe::init ( void* i_pHomerBuf )
    {
        FAPI_DBG (">> PlatSgpe::init" );
        FAPI_TRY ( collectFfdc( i_pHomerBuf, INIT),
                   "Failed To init SGPE FFDC" );

    fapi_try_exit:
        FAPI_DBG ("<< PlatSgpe::init" );
        return fapi2::current_err;
    }

    //----------------------------------------------------------------------

    fapi2::ReturnCode PlatSgpe::collectFfdc( void *  i_pHomerBuf,
                                             uint8_t i_ffdcType )
    {
        FAPI_DBG(">> PlatSgpe::collectFfdc");

        fapi2::ReturnCode l_retCode = fapi2::FAPI2_RC_SUCCESS;

        HomerFfdcRegion * l_pHomerFfdc =
                ( HomerFfdcRegion *)( (uint8_t *)i_pHomerBuf + FFDC_REGION_HOMER_BASE_OFFSET );

        uint8_t* l_pFfdcLoc = (uint8_t *)(&l_pHomerFfdc->iv_sgpeFfdcRegion);
        PpeFfdcHeader* l_pSgpeFfdcHdr = (PpeFfdcHeader*) l_pFfdcLoc;

        uint16_t l_ffdcValdityVect = l_pSgpeFfdcHdr->iv_sectionsValid;

        if ( i_ffdcType & INIT )
        {   // overwrite on init
            l_ffdcValdityVect = PPE_FFDC_INVALID;
        }

        //In case of error , invalidate FFDC in header.
        if ( i_ffdcType & PPE_HALT_STATE )
        {
            l_ffdcValdityVect |= PPE_HALT_STATE_VALID;
            l_retCode = readPpeHaltState ( SGPE_BASE_ADDRESS, l_pFfdcLoc );
            if ( l_retCode != fapi2::FAPI2_RC_SUCCESS )
            {
                FAPI_ERR ( "Error collecting SGPE Halt State" );
                l_ffdcValdityVect &= ~PPE_HALT_STATE_VALID;
            }
        }

        if ( i_ffdcType & PPE_STATE )
        {
            l_ffdcValdityVect |= PPE_STATE_VALID;
            l_retCode = collectPpeState ( SGPE_BASE_ADDRESS, l_pFfdcLoc );
            if ( l_retCode != fapi2::FAPI2_RC_SUCCESS )
            {
                FAPI_ERR ( "Error collecting SGPE State" );
                // PPE State Data is bad & continue SRAM FFDC collection
                l_ffdcValdityVect &= ~PPE_STATE_VALID;
            }
        }

        if ( i_ffdcType & TRACES )
        {
            l_ffdcValdityVect |= PPE_TRACE_VALID;
            l_retCode = collectTrace( l_pFfdcLoc );
            if( l_retCode )
            {
                FAPI_ERR("Error in collecting SGPE Trace " );
                l_ffdcValdityVect &= ~PPE_TRACE_VALID;
            }
        }

        if ( i_ffdcType & DASH_BOARD_VAR )
        {
            l_ffdcValdityVect |= PPE_DASHBOARD_VALID;
            l_retCode = collectGlobals( l_pFfdcLoc );

            if( l_retCode )
            {
                FAPI_ERR("Error in collecting SGPE Globals" );
                l_ffdcValdityVect &= ~PPE_DASHBOARD_VALID;
            }
        }

        if ( i_ffdcType & IMAGE_HEADER )
        {
            l_ffdcValdityVect |= PPE_IMAGE_HEADER_VALID;
            l_retCode = collectImageHeader( l_pFfdcLoc );

            if( l_retCode )
            {
                FAPI_ERR("Error in collecting SGPE Image header" );
                l_ffdcValdityVect &= ~PPE_IMAGE_HEADER_VALID;
            }
        }

        FAPI_TRY( updateSgpeFfdcHeader( l_pFfdcLoc, l_ffdcValdityVect),
                          "Failed To Update SGPE FFDC Header for SGPE " );

        if (l_ffdcValdityVect == PPE_FFDC_INVALID)
            setPmFfdcSectionValid ( i_pHomerBuf, PM_FFDC_SGPE_VALID, false );
        else
            setPmFfdcSectionValid ( i_pHomerBuf, PM_FFDC_SGPE_VALID );

    fapi_try_exit:
        FAPI_DBG("<< PlatSgpe::collectFfdc: 0x%02X", l_ffdcValdityVect);
        return fapi2::current_err;
    }

    //-----------------------------------------------------------------------

    fapi2::ReturnCode PlatSgpe::collectTrace( uint8_t * i_pTraceBuf )
    {
        FAPI_DBG(">> PlatSgpe::collectTrace" );
        PpeFfdcLayout * l_pSgpeFfdc = ( PpeFfdcLayout *) ( i_pTraceBuf );

        uint8_t * l_pTraceLoc = &l_pSgpeFfdc->iv_ppeTraces[0];

        FAPI_TRY( PlatPmComplex::collectSramInfo
                    ( PlatPmComplex::getProcChip(),
                      l_pTraceLoc,
                      TRACES,
                      FFDC_PPE_TRACES_SIZE ),
                  "Trace Collection Failed" );

        fapi_try_exit:
        FAPI_DBG("<< PlatSgpe::collectTrace" );
        return fapi2::current_err;
    }

    //-----------------------------------------------------------------------

    fapi2::ReturnCode  PlatSgpe::collectGlobals( uint8_t * i_pSgpeGlobals )
    {
        FAPI_DBG(">> PlatSgpe::collectGlobals" );
        PpeFfdcLayout * l_pSgpeFfdc = ( PpeFfdcLayout *) ( i_pSgpeGlobals );
        uint8_t * l_pTraceLoc = &l_pSgpeFfdc->iv_ppeGlobals[0];

        FAPI_TRY( PlatPmComplex::collectSramInfo
                    ( PlatPmComplex::getProcChip(),
                      l_pTraceLoc,
                      DASH_BOARD_VAR,
                      OCC_SRAM_SGPE_DASHBOARD_SIZE ),
                  "Failed To Collect SGPE Global Variables" );


        fapi_try_exit:
        FAPI_DBG("<< PlatSgpe::collectGlobals" );
        return fapi2::current_err;
    }

    //-----------------------------------------------------------------------

    fapi2::ReturnCode PlatSgpe::collectInternalReg( uint8_t * i_pSgpeIntReg )
    {
        return fapi2::FAPI2_RC_SUCCESS;
    }

    //-----------------------------------------------------------------------

    fapi2::ReturnCode PlatSgpe::collectImageHeader( uint8_t * i_pSgpeImgHdr )
    {
        FAPI_DBG(">> PlatSgpe::collectImageHeader" );
        PpeFfdcLayout *l_pSgpeFfdc = ( PpeFfdcLayout *) ( i_pSgpeImgHdr );

        uint8_t * l_pTraceLoc = &l_pSgpeFfdc->iv_ppeImageHeader[0];
        FAPI_TRY( PlatPmComplex::collectSramInfo
                  ( PlatPmComplex::getProcChip(),
                    l_pTraceLoc,
                    IMAGE_HEADER,
                    FFDC_PPE_IMG_HDR_SIZE ),
                  "Failed To Collect SGPE Image Header" );

        fapi_try_exit:
        FAPI_DBG("<< PlatSgpe::collectImageHeader" );
        return fapi2::current_err;
    }

    //-----------------------------------------------------------------------

    fapi2::ReturnCode PlatSgpe::updateSgpeFfdcHeader( uint8_t* i_pHomerBuf,
                                                      uint16_t i_sectionsValid )
    {
        FAPI_DBG(">> updateSgpeFfdcHeader" );

        PpeFfdcHeader * l_pSgpeFfdcHdr       =  ( (PpeFfdcHeader *)(( PpeFfdcHdrRegion * ) i_pHomerBuf ));
        l_pSgpeFfdcHdr->iv_ppeMagicNumber    =  htobe32( FFDC_SGPE_MAGIC_NUM );
        l_pSgpeFfdcHdr->iv_ppeNumber         =  0;
        PlatPmComplex::updatePpeFfdcHeader( l_pSgpeFfdcHdr, i_sectionsValid );

        FAPI_DBG("<< updateSgpeFfdcHeader" );
        return fapi2::FAPI2_RC_SUCCESS;
    }
    //-----------------------------------------------------------------------

extern "C"
{
    fapi2::ReturnCode p9_pm_recovery_ffdc_sgpe( const fapi2::Target<fapi2::TARGET_TYPE_PROC_CHIP >& i_procChip,
                                                void * i_pFfdcBuf )
    {
        FAPI_IMP(">> p9_pm_recovery_sgpe" );

        PlatSgpe l_sgpeFfdc( i_procChip );
        FAPI_TRY( l_sgpeFfdc.collectFfdc( i_pFfdcBuf, (ALL & ~PPE_HALT_STATE) ),
                  "Failed To Collect SGPE FFDC" );

        fapi_try_exit:
        FAPI_IMP("<< p9_pm_recovery_sgpe" );
        return fapi2::current_err;
    }

}


}//namespace p9_stop_recov_ffdc ends
