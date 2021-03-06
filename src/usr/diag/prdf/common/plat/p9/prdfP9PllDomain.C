/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/usr/diag/prdf/common/plat/p9/prdfP9PllDomain.C $          */
/*                                                                        */
/* OpenPOWER HostBoot Project                                             */
/*                                                                        */
/* Contributors Listed Below - COPYRIGHT 2016,2017                        */
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

/** @file  prdfPllDomain.C
 *  @brief Definition of PllDomain class
 */

#include <prdfPllDomain.H>

#include <CcAutoDeletePointer.h>
#include <iipscr.h>
#include <iipsdbug.h>
#include <iipServiceDataCollector.h>
#include <prdfErrorSignature.H>
#include <iipResolution.h>
#include <prdfPlatServices.H>
#include <prdfPluginDef.H>
#include <prdfGlobal.H>
#include <iipSystem.h>
#include <UtilHash.H>
#include <prdfP9Pll.H>

#include <prdfP9ProcMbCommonExtraSig.H>

using namespace TARGETING;

namespace PRDF
{

using namespace PlatServices;
using namespace PLL;

//------------------------------------------------------------------------------

int32_t PllDomain::Initialize(void)
{

  int32_t rc = SUCCESS;
  return(rc);
}

//------------------------------------------------------------------------------

bool PllDomain::Query(ATTENTION_TYPE attentionType)
{
    bool atAttn = false;
    // System always checks for RE's first, even if there is an XSTOP
    // So we only need to check for PLL errors on RECOVERABLE type
    if(attentionType == RECOVERABLE)
    {
        // check sysdbug for attention first
        SYSTEM_DEBUG_CLASS sysdbug;
        for(unsigned int index = 0; (index < GetSize()) && (atAttn == false);
            ++index)
        {
            ExtensibleChip * l_chip = LookUp( index );
            TARGETING::TargetHandle_t l_chipTgt = l_chip->getTrgt();
            bool l_analysisPending =
                  sysdbug.isActiveAttentionPending( l_chipTgt, RECOVERABLE );

            if( l_analysisPending )
            {
                ExtensibleChipFunction * l_query =
                                    l_chip->getExtensibleFunction("QueryPll");
                int32_t rc = (*l_query)
                    (l_chip,PluginDef::bindParm<bool &>(atAttn));

                // if rc then scom read failed
                // Error log has already been generated
                if( PRD_POWER_FAULT == rc )
                {
                    PRDF_ERR( "prdfPllDomain::Query() Power Fault detected!" );
                    break;
                }
                else if(SUCCESS != rc)
                {
                    PRDF_ERR( "prdfPllDomain::Query() SCOM fail. RC=%x", rc );
                }
            }
        }
    }

    return(atAttn);
}

//------------------------------------------------------------------------------

int32_t PllDomain::Analyze(STEP_CODE_DATA_STRUCT & serviceData,
                          ATTENTION_TYPE attentionType)
{
    #define PRDF_FUNC "[PllDomain::Analyze] "
    std::vector<ExtensibleChip *> sysRefList;
    std::vector<ExtensibleChip *> pciList;
    std::vector<ExtensibleChip *> mfFoList;
    std::vector<ExtensibleChip *> sysRefFoList;
    int32_t rc = SUCCESS;
    uint32_t mskErrType =  0;

    // Due to clock issues some chips may be moved to non-functional during
    // analysis. In this case, these chips will need to be removed from their
    // domains.
    std::vector<ExtensibleChip *>  nfchips;

    // Examine each chip in domain
    for(unsigned int index = 0; index < GetSize(); ++index)
    {
        uint32_t l_errType = 0;

        ExtensibleChip * l_chip = LookUp(index);

        // Check if this chip has a clock error
        ExtensibleChipFunction * l_query =
            l_chip->getExtensibleFunction("CheckErrorType");
        rc |= (*l_query)(l_chip,
            PluginDef::bindParm<uint32_t &> (l_errType));

        if ( !PlatServices::isFunctional(l_chip->getTrgt()) )
        {
            // The chip is now non-functional.
            nfchips.push_back( l_chip );
        }

        // Get this chip's capture data for any error
        if (0 != l_errType)
        {
            l_chip->CaptureErrorData(
                    serviceData.service_data->GetCaptureData());
            // Capture PllFIRs group
            l_chip->CaptureErrorData(
                    serviceData.service_data->GetCaptureData(),
                    Util::hashString("PllFIRs"));

            // Call this chip's capturePllFfdc plugin if it exists.
            ExtensibleChipFunction * l_captureFfdc =
                l_chip->getExtensibleFunction("capturePllFfdc", true);
            if ( NULL != l_captureFfdc )
            {
                (*l_captureFfdc)( l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT &>(serviceData) );
            }
        }

        // In the case of a PLL_UNLOCK error, we want to do additional isolation
        // in case of a HWP failure
        ExtensibleChipFunction * l_hwpErrIsolation =
            l_chip->getExtensibleFunction("HwpErrorIsolation");

        // Update error lists
        if (l_errType & SYS_PLL_UNLOCK)
        {
            sysRefList.push_back( l_chip );
            (*l_hwpErrIsolation)(l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));
        }
        if (l_errType & PCI_PLL_UNLOCK)
        {
            pciList.push_back( l_chip );
            (*l_hwpErrIsolation)(l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));
        }
        if (l_errType & SYS_OSC_FAILOVER)
            mfFoList.push_back( l_chip );
        if (l_errType & PCI_OSC_FAILOVER)
            sysRefFoList.push_back( l_chip );


    } // end for each chip in domain

    // Remove all non-functional chips.
    if ( CHECK_STOP != serviceData.service_data->getPrimaryAttnType() )
    {
        for (  auto i : nfchips )
        {
            systemPtr->RemoveStoppedChips( i->getTrgt() );
        }
    }

    // TODO: RTC 155673 - use attributes to callout active clock sources
    // For Nimbus sys ref and mf ref clock source is the same

    // always suspect the clock source
    closeClockSource.Resolve(serviceData);
    if(&closeClockSource != &farClockSource)
    {
        farClockSource.Resolve(serviceData);
    }

    if (sysRefList.size() > 0 || pciList.size() > 0)
    {
        iv_threshold.Resolve(serviceData);
    }

    if (sysRefList.size() > 0 )
    {
         // Test for threshold
        if(serviceData.service_data->IsAtThreshold())
        {
            mskErrType |= SYS_PLL_UNLOCK;
        }

        // Set Signature
        serviceData.service_data->GetErrorSignature()->
            setChipId(sysRefList[0]->getHuid());
        serviceData.service_data->SetErrorSig( PRDFSIG_PLL_ERROR );

        // If only one detected sys ref error, add it to the callout list.
        if (sysRefList.size() == 1)
        {
            const uint32_t tmpCount =
                serviceData.service_data->getMruListSize();

            // Call this chip's CalloutPll plugin if it exists.
            ExtensibleChipFunction * l_callout =
                    sysRefList[0]->getExtensibleFunction( "CalloutPll", true );
            if ( NULL != l_callout )
            {
                (*l_callout)( sysRefList[0],
                    PluginDef::bindParm<STEP_CODE_DATA_STRUCT &>(serviceData) );
            }

            // If CalloutPll plugin does not add anything new to the callout
            // list, callout this chip
            if ( tmpCount == serviceData.service_data->getMruListSize() )
            {
                // No additional callouts were made so add this chip to the list
                serviceData.service_data->SetCallout( sysRefList[0]->getTrgt());
            }
        }
    }

    if (pciList.size() > 0)
    {
        // Test for threshold
        if(serviceData.service_data->IsAtThreshold())
        {
            mskErrType |= PCI_PLL_UNLOCK;
        }

        // Set Signature
        serviceData.service_data->GetErrorSignature()->
            setChipId(pciList[0]->getHuid());
        serviceData.service_data->SetErrorSig( PRDFSIG_PLL_ERROR );

        // If only one detected sys ref error, add it to the callout list.
        if (pciList.size() == 1)
        {
            const uint32_t tmpCount =
                serviceData.service_data->getMruListSize();

            // Call this chip's CalloutPll plugin if it exists.
            ExtensibleChipFunction * l_callout =
                    pciList[0]->getExtensibleFunction( "CalloutPll", true );
            if ( NULL != l_callout )
            {
                (*l_callout)( pciList[0],
                    PluginDef::bindParm<STEP_CODE_DATA_STRUCT &>(serviceData) );
            }

            // If CalloutPll plugin does not add anything new to the callout
            // list, callout this chip
            if ( tmpCount == serviceData.service_data->getMruListSize() )
            {
                // No additional callouts were made so add this chip to the list
                serviceData.service_data->SetCallout( sysRefList[0]->getTrgt());
            }
        }

    }

    // TODO: RTC 155673 - Handle redundant Osc failovers
    // Shouldn't see these on nimbus
    if (mfFoList.size() > 0)
    {
        PRDF_ERR( PRDF_FUNC "Unexpected PCI osc failover detected" );
        mskErrType |= PCI_OSC_FAILOVER;
        serviceData.service_data->SetCallout( LEVEL2_SUPPORT, MRU_LOW );
    }
    if (sysRefFoList.size() > 0)
    {
        PRDF_ERR( PRDF_FUNC "Unexpected Sys osc failover detected" );
        mskErrType |= SYS_OSC_FAILOVER;
        serviceData.service_data->SetCallout( LEVEL2_SUPPORT, MRU_LOW );
    }

    if (serviceData.service_data->IsAtThreshold())
    {
        // Mask appropriate errors on all chips in domain
        ExtensibleDomainFunction * l_mask =
                            getExtensibleFunction("MaskPll");
        (*l_mask)(this,
              PluginDef::bindParm<STEP_CODE_DATA_STRUCT&, uint32_t>
                  (serviceData, mskErrType));
    }

    // Clear PLLs from this domain.
    ExtensibleDomainFunction * l_clear = getExtensibleFunction("ClearPll");
    (*l_clear)(this,
               PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));

    // Run PLL Post Analysis on any analyzed chips in this domain.
    for(auto l_chip : sysRefList)
    {
        // Send any special messages indicating there was a PLL error.
        ExtensibleChipFunction * l_pllPostAnalysis =
                l_chip->getExtensibleFunction("PllPostAnalysis", true);
        (*l_pllPostAnalysis)(l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));
    }

    for(auto l_chip : pciList)
    {
        // Send any special messages indicating there was a PLL error.
        ExtensibleChipFunction * l_pllPostAnalysis =
                l_chip->getExtensibleFunction("PllPostAnalysis", true);
        (*l_pllPostAnalysis)(l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));
    }

    for(auto l_chip : mfFoList)
    {
        // Send any special messages indicating there was a PLL error.
        ExtensibleChipFunction * l_pllPostAnalysis =
                l_chip->getExtensibleFunction("PllPostAnalysis", true);
        (*l_pllPostAnalysis)(l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));
    }
    for(auto l_chip : sysRefFoList)
    {
        // Send any special messages indicating there was a PLL error.
        ExtensibleChipFunction * l_pllPostAnalysis =
                l_chip->getExtensibleFunction("PllPostAnalysis", true);
        (*l_pllPostAnalysis)(l_chip,
                PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(serviceData));
    }

    return rc;

    #undef PRDF_FUNC
}

//------------------------------------------------------------------------------

void PllDomain::Order(ATTENTION_TYPE attentionType)
{
    // Order is not important for PLL errors
}

//------------------------------------------------------------------------------

int32_t PllDomain::ClearPll( ExtensibleDomain * i_domain,
                             STEP_CODE_DATA_STRUCT & i_sc )
{
    PllDomain * l_domain = (PllDomain *) i_domain;

    const char * clearPllFuncName = "ClearPll";

    // Clear children chips.
    for ( uint32_t i = 0; i < l_domain->GetSize(); i++ )
    {
        ExtensibleChip * l_chip = l_domain->LookUp(i);
        ExtensibleChipFunction * l_clear =
                        l_chip->getExtensibleFunction(clearPllFuncName);
        (*l_clear)( l_chip,
                    PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(i_sc) );
    }

    // Clear children domains.
    // This looks like a recursive call.  It calls other domains of Clear.
    ParentDomain<ExtensibleDomain>::iterator i;
    for (i = l_domain->getBeginIterator(); i != l_domain->getEndIterator(); i++)
    {
        // Clear PLLs from this domain.
        ExtensibleDomainFunction * l_clear =
                                (i->second)->getExtensibleFunction("ClearPll");
        (*l_clear)( i->second,
                    PluginDef::bindParm<STEP_CODE_DATA_STRUCT&>(i_sc) );
    }

    return SUCCESS;
}
PRDF_PLUGIN_DEFINE( PllDomain, ClearPll );

//------------------------------------------------------------------------------

int32_t PllDomain::MaskPll( ExtensibleDomain * i_domain,
                            STEP_CODE_DATA_STRUCT & i_sc,
                            uint32_t i_errType )
{
    PllDomain * l_domain = (PllDomain *) i_domain;

    // Mask children chips.
    for ( uint32_t i = 0; i < l_domain->GetSize(); i++ )
    {
        ExtensibleChip * l_chip = l_domain->LookUp(i);
        ExtensibleChipFunction * l_mask =
                            l_chip->getExtensibleFunction("MaskPll");
        (*l_mask)( l_chip,
            PluginDef::bindParm<STEP_CODE_DATA_STRUCT&, uint32_t>
                (i_sc, i_errType) );
    }

    // Mask children domains.
    // This looks like a recursive call.  It calls other domains of Mask.
    ParentDomain<ExtensibleDomain>::iterator i;
    for (i = l_domain->getBeginIterator(); i != l_domain->getEndIterator(); i++)
    {
        ExtensibleDomainFunction * l_mask =
                                (i->second)->getExtensibleFunction("MaskPll");
        (*l_mask)( i->second,
            PluginDef::bindParm<STEP_CODE_DATA_STRUCT&, uint32_t>
                (i_sc, i_errType) );
    }

    return SUCCESS;
}
PRDF_PLUGIN_DEFINE( PllDomain, MaskPll );

//------------------------------------------------------------------------------

} // end namespace PRDF

