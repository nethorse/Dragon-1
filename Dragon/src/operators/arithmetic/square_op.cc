#include "utils/math_functions.h"
#include "operators/arithmetic/square_op.h"

namespace dragon {

template <class Context> template <typename T>
void SquareOp<Context>::RunWithType() {
    auto* Xdata = Input(0).template data<T, Context>();
    auto* Ydata = Output(0)->template mutable_data<T, Context>();
    math::Pow<T, Context>(Output(0)->count(), 2.0, Xdata, Ydata, ctx());
}

template <class Context>
void SquareOp<Context>::RunOnDevice() {
    Output(0)->ReshapeLike(Input(0));

    if (XIsType(Input(0), float)) RunWithType<float>();
    else LOG(FATAL) << DTypeHelper(Input(0), { "float32" });
}

DEPLOY_CPU(Square);
#ifdef WITH_CUDA
DEPLOY_CUDA(Square);
#endif
OPERATOR_SCHEMA(Square).NumInputs(1).NumOutputs(1);

template <class Context> template <typename T>
void SquareGradientOp<Context>::RunWithType() {
    auto* Xdata = Input(0).template data<T, Context>();
    auto* dYdata = Input(-1).template data<T, Context>();
    auto* dXdata = Output(0)->template mutable_data<T, Context>();
    math::Mul<T, Context>(Output(0)->count(), dYdata, Xdata, dXdata, ctx());
    math::Scal<T, Context>(Output(0)->count(), 2.0, dXdata, ctx());
}

template <class Context>
void SquareGradientOp<Context>::RunOnDevice() {
    Output(0)->ReshapeLike(Input(0));

    if (XIsType(Input(0), float)) RunWithType<float>();
    else LOG(FATAL) << DTypeHelper(Input(0), { "float32" });
}

DEPLOY_CPU(SquareGradient);
#ifdef WITH_CUDA
DEPLOY_CUDA(SquareGradient);
#endif
OPERATOR_SCHEMA(SquareGradient).NumInputs(2).NumOutputs(1);

class GetSquareGradient final : public GradientMakerBase {
 public:
    GRADIENT_MAKER_CTOR(GetSquareGradient);
    vector<OperatorDef> MakeDefs() override{
        return SingleDef(def.type() + "Gradient", "",
            vector<string> {I(0), GO(0)},
            vector<string> {GI(0)});
    }
};
REGISTER_GRADIENT(Square, GetSquareGradient);

}    // namespace dragon