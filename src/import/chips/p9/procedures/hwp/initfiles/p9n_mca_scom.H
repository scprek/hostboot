/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/import/chips/p9/procedures/hwp/initfiles/p9n_mca_scom.H $ */
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
#ifndef _INIT_P9N_MCA_SCOM_PROCEDURE_H_
#define _INIT_P9N_MCA_SCOM_PROCEDURE_H_


#include <stddef.h>
#include <stdint.h>
#include <fapi2.H>


typedef fapi2::ReturnCode (*p9n_mca_scom_FP_t)(const fapi2::Target<fapi2::TARGET_TYPE_MCA>&,
        const fapi2::Target<fapi2::TARGET_TYPE_MCBIST>&, const fapi2::Target<fapi2::TARGET_TYPE_MCS>&,
        const fapi2::Target<fapi2::TARGET_TYPE_SYSTEM>&, const fapi2::Target<fapi2::TARGET_TYPE_PROC_CHIP>&);

extern "C"
{

    fapi2::ReturnCode p9n_mca_scom(const fapi2::Target<fapi2::TARGET_TYPE_MCA>& TGT0,
                                   const fapi2::Target<fapi2::TARGET_TYPE_MCBIST>& TGT1, const fapi2::Target<fapi2::TARGET_TYPE_MCS>& TGT2,
                                   const fapi2::Target<fapi2::TARGET_TYPE_SYSTEM>& TGT3, const fapi2::Target<fapi2::TARGET_TYPE_PROC_CHIP>& TGT4);

}

#endif
