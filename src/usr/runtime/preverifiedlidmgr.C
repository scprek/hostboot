/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/usr/runtime/preverifiedlidmgr.C $                         */
/*                                                                        */
/* OpenPOWER HostBoot Project                                             */
/*                                                                        */
/* Contributors Listed Below - COPYRIGHT 2017                             */
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
#include <runtime/preverifiedlidmgr.H>
#include <errl/errlentry.H>
#include <errl/errlmanager.H>
#include <utility>
#include <runtime/populate_hbruntime.H>
#include <util/align.H>
#include <util/utillidmgr.H>
#include <util/utillidpnor.H>
#include <initservice/initserviceif.H>
#include <util/singleton.H>
#include <stdio.h>
#include <arch/ppc.H>

extern trace_desc_t *g_trac_runtime;

// Set static variables
TARGETING::PAYLOAD_KIND PreVerifiedLidMgr::cv_payloadKind = TARGETING::PAYLOAD_KIND_NONE;
std::map<uint64_t,bool> PreVerifiedLidMgr::cv_lidsLoaded {};
bool PreVerifiedLidMgr::cv_phypLidSeen = false;
PreVerifiedLidMgr::ResvMemInfo* PreVerifiedLidMgr::cv_pResvMemInfo = nullptr;
PreVerifiedLidMgr::ResvMemInfo PreVerifiedLidMgr::cv_resvMemInfo {};
PreVerifiedLidMgr::ResvMemInfo PreVerifiedLidMgr::cv_phypResvMemInfo {};
mutex_t PreVerifiedLidMgr::cv_mutex = MUTEX_INITIALIZER;
mutex_t PreVerifiedLidMgr::cv_loadImageMutex = MUTEX_INITIALIZER;

/********************
 Public Methods
 ********************/

void PreVerifiedLidMgr::initLock(const uint64_t i_prevAddr,
                                 const uint64_t i_prevSize,
                                 const size_t i_rangeId)
{
    Singleton<PreVerifiedLidMgr>::instance()._initLock(i_prevAddr,
                                                       i_prevSize,
                                                       i_rangeId);
}

void PreVerifiedLidMgr::unlock()
{
    Singleton<PreVerifiedLidMgr>::instance()._unlock();
}


errlHndl_t PreVerifiedLidMgr::loadFromPnor(const PNOR::SectionId i_sec,
                                           const uint64_t i_addr,
                                           const size_t i_size)
{
    return Singleton<PreVerifiedLidMgr>::instance()._loadFromPnor(i_sec,
                                                                  i_addr,
                                                                  i_size);
}

/********************
 Private Implementations of Static Public Methods
 ********************/

void PreVerifiedLidMgr::_initLock(const uint64_t i_prevAddr,
                                  const uint64_t i_prevSize,
                                  const size_t i_rangeId)
{
    mutex_lock(&cv_mutex);

    cv_payloadKind = TARGETING::PAYLOAD_KIND_NONE;
    cv_phypLidSeen = false;

    // Default Reserved Memory Information
    cv_resvMemInfo.rangeId = i_rangeId;
    cv_resvMemInfo.curAddr = i_prevAddr;
    cv_resvMemInfo.prevSize = i_prevSize;

    // PHYP Reserved Memory Information
    cv_phypResvMemInfo.rangeId = i_rangeId;
    // PHYP lids loaded at HRMOR - 4K (Header)
    // Get Target Service, and the system target.
    TARGETING::Target* l_sys = nullptr;
    TARGETING::targetService().getTopLevelTarget(l_sys);
    assert(l_sys!=nullptr,"Top Level Target is nullptr");
    cv_phypResvMemInfo.curAddr = (l_sys->getAttr<TARGETING::ATTR_PAYLOAD_BASE>()
                                 * MEGABYTE) - PAGE_SIZE;

    // PHYP should be placed starting exactly at HRMOR - 4K, so make prevSize 0
    cv_phypResvMemInfo.prevSize = 0;

    // Refer to default reserved memory
    cv_pResvMemInfo = &cv_resvMemInfo;

    // Set variables based on payload Kind
    // Note: For PHYP we build up starting at the end of the
    //       previously allocated HOMER/OCC areas, for OPAL we build
    //       downwards from the top of memory where the HOMER/OCC
    //       areas were placed

    // Set default next physical address to simply increment in order
    getNextAddress = getNextPhypAddress;

    if(TARGETING::is_phyp_load())
    {
        cv_payloadKind = TARGETING::PAYLOAD_KIND_PHYP;
    }
    else if(TARGETING::is_sapphire_load())
    {
        cv_payloadKind = TARGETING::PAYLOAD_KIND_SAPPHIRE;
        getNextAddress = getNextOpalAddress;
    }
}

void PreVerifiedLidMgr::_unlock()
{
    TRACFCOMP(g_trac_runtime, "PreVerifiedLidMgr::_unlock");
    mutex_unlock(&cv_mutex);
}

errlHndl_t PreVerifiedLidMgr::_loadFromPnor(const PNOR::SectionId i_sec,
                                            const uint64_t i_addr,
                                            const size_t i_size)
{
    mutex_lock(&cv_loadImageMutex);

    TRACFCOMP(g_trac_runtime, ENTER_MRK"PreVerifiedLidMgr::_loadFromPnor - sec %s",
              PNOR::SectionIdToString(i_sec));

    errlHndl_t l_errl = nullptr;

    do {

    // Translate Pnor Section Id to Lid
    auto l_lids = Util::getPnorSecLidIds(i_sec);
    TRACFCOMP( g_trac_runtime, "PreVerifiedLidMgr::loadFromPnor - getPnorSecLidIds lid = 0x%X, containerLid = 0x%X",
            l_lids.lid, l_lids.containerLid);
    assert(l_lids.lid != Util::INVALID_LIDID,"Pnor Section = %s not associated with any Lids", PNOR::SectionIdToString(i_sec));

    // Only load if not previously done.
    if( isLidLoaded(l_lids.containerLid) && isLidLoaded(l_lids.lid) )
    {
        TRACFCOMP( g_trac_runtime, "PreVerifiedLidMgr::loadFromPnor - sec %s already loaded",
                PNOR::SectionIdToString(i_sec));
        break;
    }

    // Get next available HB resverved memory address
    cv_pResvMemInfo->curAddr = getNextAddress(i_size);

    // @TODO RTC:178163 remove need for l_loadImage
    bool l_loadImage = false;
    if(cv_payloadKind == TARGETING::PAYLOAD_KIND_PHYP)
    {
        // @TODO RTC:178163 enable when we can Load ALL pre-verfied lids
        // There are checks in phyp for ANY hdat entry marked "RHB_TYPE_VERIFIED_LIDS"
        // If there are any missing phyp will fail to boot.
/*
        l_loadImage = true;
        // Verified Lid - Header Only
        if ( (l_lids.containerLid != INVALID_LIDID) &&
             !isLidLoaded(l_lids.containerLid))
        {
            char l_containerLidStr [Util::lidIdStrLength] {};
            snprintf (l_containerLidStr, Util::lidIdStrLength, "%08X",
                    l_lids.containerLid);
            l_errl = RUNTIME::setNextHbRsvMemEntry(HDAT::RHB_TYPE_VERIFIED_LIDS,
                                                   cv_pResvMemInfo->rangeId,
                                                   cv_pResvMemInfo->curAddr,
                                                   getAlignedSize(PAGE_SIZE),
                                                   l_containerLidStr);
            if(l_errl)
            {
                TRACFCOMP( g_trac_runtime, ERR_MRK"PreVerifiedLidMgr::loadFromPnor - setNextHbRsvMemEntry Lid header failed");
                break;
            }
        }

        // Verified Lid - Content Only
        if ( (l_lids.lid != INVALID_LIDID) &&
             !isLidLoaded(l_lids.lid))
        {
            char l_lidStr[Util::lidIdStrLength] {};
            snprintf (l_lidStr, Util::lidIdStrLength, "%08X",l_lids.lid);
            l_errl = RUNTIME::setNextHbRsvMemEntry(HDAT::RHB_TYPE_VERIFIED_LIDS,
                                                   cv_pResvMemInfo->rangeId,
                                                   cv_pResvMemInfo->curAddr+PAGE_SIZE,
                                                   getAlignedSize(i_size),
                                                   l_lidStr);
            if(l_errl)
            {
                TRACFCOMP( g_trac_runtime, ERR_MRK"PreVerifiedLidMgr::loadFromPnor - setNextHbRsvMemEntry Lid content failed");
                break;
            }
        }
*/
    }
    else if(cv_payloadKind == TARGETING::PAYLOAD_KIND_SAPPHIRE)
    {
        l_loadImage = true;
        // Verified PNOR - Header + Content
        l_errl = RUNTIME::setNextHbRsvMemEntry(HDAT::RHB_TYPE_VERIFIED_PNOR,
                                               cv_pResvMemInfo->rangeId,
                                               cv_pResvMemInfo->curAddr,
                                               getAlignedSize(i_size),
                                               PNOR::SectionIdToString(i_sec),
                                               HDAT::RHB_READ_ONLY);
        if(l_errl)
        {
            TRACFCOMP( g_trac_runtime, ERR_MRK"PreVerifiedLidMgr::loadFromPnor - setNextHbRsvMemEntry PNOR content failed");
            break;
        }
    }

    if (l_loadImage)
    {
        // Load image into HB reserved memory
        l_errl = loadImage(i_addr, i_size);
        if(l_errl)
        {
            TRACFCOMP( g_trac_runtime, ERR_MRK"PreVerifiedLidMgr::loadFromPnor - setNextHbRsvMemEntry PNOR content failed");
            break;
        }
    }

    // Indicate the full PNOR section has been loaded.
    // Include both the header and content lids
    cv_lidsLoaded.insert(std::make_pair(l_lids.containerLid, true));
    cv_lidsLoaded.insert(std::make_pair(l_lids.lid, true));

    } while(0);

    TRACFCOMP( g_trac_runtime, EXIT_MRK"PreVerifiedLidMgr::_loadFromPnor");

    mutex_unlock(&cv_loadImageMutex);

    return l_errl;
}

/********************
 Private/Protected Methods
 ********************/

PreVerifiedLidMgr& PreVerifiedLidMgr::getInstance()
{
    return Singleton<PreVerifiedLidMgr>::instance();
}

uint64_t PreVerifiedLidMgr::getAlignedSize(const size_t i_imgSize)
{
    return ALIGN_X(i_imgSize, HBRT_RSVD_MEM_OPAL_ALIGN);
}

uint64_t PreVerifiedLidMgr::getNextPhypAddress(const size_t i_prevSize)
{
    return cv_pResvMemInfo->curAddr + cv_pResvMemInfo->prevSize;
}

uint64_t PreVerifiedLidMgr::getNextOpalAddress(const size_t i_curSize)
{
    return cv_pResvMemInfo->curAddr - getAlignedSize(i_curSize);
}

bool PreVerifiedLidMgr::isLidLoaded(uint32_t i_lidId)
{
    bool l_loaded = false;

    if (cv_lidsLoaded.count(i_lidId) > 0)
    {
        l_loaded = true;
    }

    return l_loaded;
}

errlHndl_t PreVerifiedLidMgr::loadImage(const uint64_t i_imgAddr,
                                        const size_t i_imgSize)
{
    TRACFCOMP( g_trac_runtime, ENTER_MRK"PreVerifiedLidMgr::loadImage");

    errlHndl_t l_errl = nullptr;

    do {

    uint64_t l_tmpVaddr = 0;
    // Load the Verified image into HB resv memory
    l_errl = RUNTIME::mapPhysAddr(cv_pResvMemInfo->curAddr, i_imgSize, l_tmpVaddr);
    if(l_errl)
    {
        TRACFCOMP( g_trac_runtime, ERR_MRK"PreVerifiedLidMgr::loadImage - mapPhysAddr failed");
        break;
    }

    // Include Header page from pnor image.
    memcpy(reinterpret_cast<void*>(l_tmpVaddr),
           reinterpret_cast<void*>(i_imgAddr),
           i_imgSize);

    l_errl = RUNTIME::unmapVirtAddr(l_tmpVaddr);
    if(l_errl)
    {
        TRACFCOMP( g_trac_runtime, ERR_MRK"PreVerifiedLidMgr::loadImage - unmapVirtAddr failed");
        break;
    }

    // Update previous size using aligned size for OPAL alignment even if that
    // means there is some wasted space.
    cv_pResvMemInfo->prevSize = getAlignedSize(i_imgSize);

    } while(0);

    TRACFCOMP( g_trac_runtime, EXIT_MRK"PreVerifiedLidMgr::loadImage");

    return l_errl;
}