/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/import/chips/p9/procedures/hwp/cache/p9_l2err_linedelete.H $ */
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

///----------------------------------------------------------------------------
///
/// @file p9_l2err_linedelete.H
///
/// @brief Delete the L2 error cache line according to the error extraction
///        information.
///
/// Write member, cgc address and bank into PRD Purge Engine Command Register
/// SCOM Addr: 0x000000001001080E
/// bit 0 is the trigger, the act of writing this bit to 1 sets off the line delete
/// bits 1:4 is the ttype 0b0010 = line delete
/// bits 17:19 is the member
/// bits 20:27 is the cgc address
/// bit 28 is the bank
///
/// NOTE: The error information is extracted by the HWP p9_l2err_extract.
///       An output data structure is dumped to this proceder and wrapped
///
/// *HWP HWP Owner   : Chen Qian <qianqc@cn.ibm.com>
/// *HWP FW Owner    : Thi Tran <thi@us.ibm.com>
/// *HWP Team        : Quad
/// *HWP Consumed by : PRDF
/// *HWP Level       : 3
///----------------------------------------------------------------------------
#ifndef _P9_L2ERR_LINEDELETE_H_
#define _P9_L2ERR_LINEDELETE_H_

//------------------------------------------------------------------------------
// Includes
//------------------------------------------------------------------------------
#include <fapi2.H>
#include <p9_l2err_extract.H>

// function pointer typedef definition for HWP call support
typedef fapi2::ReturnCode (*p9_l2err_linedelete_FP_t)
(const fapi2::Target<fapi2::TARGET_TYPE_EX>&,
 const p9_l2err_extract_err_data&,
 const uint64_t p9_l2err_linedelete_TryBusyCounts);

extern "C"
{

//------------------------------------------------------------------------------
// Function prototype
//------------------------------------------------------------------------------
///
/// @brief  Perform L2 Line Delete on an EX target using input L2
///         error data information.
///
/// @param[in]  i_target       => EX chiplet target
/// @param[in]  i_err_data     => L2 error data
/// @param[in]  i_busyCount    => Max busy count waiting for PURGE to complete.
///
    fapi2::ReturnCode p9_l2err_linedelete(
        const fapi2::Target<fapi2::TARGET_TYPE_EX>& i_target,
        const p9_l2err_extract_err_data& i_err_data,
        const uint64_t i_busyCount);

} // extern "C"

#endif // _P9_L2ERR_LINEDELETE_H_
