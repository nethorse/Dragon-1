// ------------------------------------------------------------
// Copyright (c) 2017-present, SeetaTech, Co.,Ltd.
//
// Licensed under the BSD 2-Clause License.
// You should have received a copy of the BSD 2-Clause License
// along with the software. If not, See,
//
//      <https://opensource.org/licenses/BSD-2-Clause>
//
// -------------------------------------------------------------

#ifndef DRAGON_OPERATORS_MPI_MPI_GATHER_OP_H_
#define DRAGON_OPERATORS_MPI_MPI_GATHER_OP_H_

#ifdef WITH_MPI

#include "operators/mpi/base_mpi_op.h"

namespace dragon {

template <class Context>
class MPIGatherOp final : public ModelMPIBase<Context> {
 public:
    MPIGatherOp(const OperatorDef& def, Workspace *ws)
        : ModelMPIBase<Context>(def, ws) {}
    USE_OPERATOR_FUNCTIONS;
    USE_MPIMODEL_FUNCTIONS(Context);

    void RunOnDevice() override;
    template <typename T> void RunWithType();
};

template <class Context>
class MPIGatherGradientOp final : public ModelMPIBase<Context> {
 public:
    MPIGatherGradientOp(const OperatorDef& def, Workspace *ws) 
        : ModelMPIBase<Context>(def, ws) {}
    USE_OPERATOR_FUNCTIONS;
    USE_MPIMODEL_FUNCTIONS(Context);

    void RunOnDevice() override;
    template <typename T> void RunWithType();
};

}    // namespace dragon

#endif // WITH_MPI

#endif    // DRAGON_OPERATORS_MPI_MPI_GATHER_OP_H_