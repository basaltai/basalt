from algorithm import vectorize
from math import exp, pow
from math.limit import min_finite, max_finite

from basalt import Tensor, TensorShape
from basalt.utils.tensorutils import elwise_transform
from basalt.autograd.attributes import Attribute, AttributeVector


@value
struct SIGMOID:
    @staticmethod
    fn result_shape(t1_shape: TensorShape) -> TensorShape:
        return t1_shape

    @staticmethod
    @always_inline
    fn sigmoid[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return 1 / (1 + exp(-x))

    @staticmethod
    @always_inline
    fn sidmoid_bw[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return Self.sigmoid(x) * (1 - Self.sigmoid(x))

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        """Forward operation of sigmoid."""
        elwise_transform[Self.sigmoid](res, t1)

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of sigmoid."""
        # d(sigmod(x))/dx = sigmoid(x) * (1 - sigmoid(x))
        var res_grad = Tensor[dtype](ug_shape)

        @parameter
        fn vec_sigmoid_bw[nelts: Int](idx: Int):
            res_grad.store[nelts](
                idx,
                Self.sidmoid_bw(t1.load[nelts](idx)) * ug.load[nelts](idx),
            )

        vectorize[vec_sigmoid_bw, nelts](ug_shape.num_elements())

        return res_grad ^


struct RELU:
    @staticmethod
    fn result_shape(t1_shape: TensorShape) -> TensorShape:
        return t1_shape

    @staticmethod
    @always_inline
    fn relu[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        # x if x > 0 else 0
        return (x > 0).select(x, 0)

    @staticmethod
    @always_inline
    fn relu_bw[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        # 1 if x > 0 else 0
        return (x > 0).select[type](1, 0)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        """Forward operation of relu."""
        elwise_transform[Self.relu](res, t1)

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of relu."""
        # d(relu(x))/dx = 1 if x > 0 else 0. We also give 0 to x = 0 instead of undefined.
        var res_grad = Tensor[dtype](ug_shape)

        @parameter
        fn vec_relu_bw[nelts: Int](idx: Int):
            res_grad.store[nelts](
                idx, Self.relu_bw(t1.load[nelts](idx)) * ug.load[nelts](idx)
            )

        vectorize[vec_relu_bw, nelts](ug_shape.num_elements())

        return res_grad ^


struct TANH:
    @staticmethod
    fn result_shape(t1_shape: TensorShape) -> TensorShape:
        return t1_shape

    @staticmethod
    @always_inline
    fn tanh[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return (exp(x) - exp(-x)) / (exp(x) + exp(-x))

    @staticmethod
    @always_inline
    fn tanh_bw[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return 1 - pow(Self.tanh(x), 2)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        """Forward operation of tanh."""
        elwise_transform[Self.tanh](res, t1)

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of tanh."""
        # d(tanh(x))/dx = 1 - tanh(x) ** 2
        var res_grad = Tensor[dtype](ug_shape)

        @parameter
        fn vec_tanh_bw[nelts: Int](idx: Int):
            res_grad.store[nelts](
                idx, Self.tanh_bw(t1.load[nelts](idx)) * ug.load[nelts](idx)
            )

        vectorize[vec_tanh_bw, nelts](ug_shape.num_elements())

        return res_grad ^


struct CLIP:
    @staticmethod
    fn result_shape(t_shape: TensorShape) -> TensorShape:
        return t_shape

    @staticmethod
    fn forward[
        t_shape: TensorShape, attributes: AttributeVector
    ](inout res: Tensor[dtype], t: Tensor[dtype]):
        """
        Forward pass of the clip operation.
        """
        alias min_attr = attributes["min"]
        alias max_attr = attributes["max"]

        var min_val = min_attr.value().to_scalar[dtype]() if min_attr else min_finite[
            dtype
        ]()
        var max_val = max_attr.value().to_scalar[dtype]() if max_attr else max_finite[
            dtype
        ]()

        @parameter
        fn vec_clip[nelts: Int](i: Int):
            res.store[nelts](i, t.load[nelts](i).min(max_val).max(min_val))

        vectorize[vec_clip, nelts, size = t_shape.num_elements()]()

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t_shape: TensorShape,
        attributes: AttributeVector = AttributeVector(),
    ](ug: Tensor[dtype], t: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of clip."""
        alias min_attr = attributes["min"]
        alias max_attr = attributes["max"]

        var min_val = min_attr.value().to_scalar[dtype]() if min_attr else min_finite[
            dtype
        ]()
        var max_val = max_attr.value().to_scalar[dtype]() if max_attr else max_finite[
            dtype
        ]()

        var res_grad = Tensor[dtype](t_shape)

        @parameter
        fn vec_clip_bw[nelts: Int](i: Int):
            var val = t.load[nelts](i)
            res_grad.store[nelts](
                i,
                ((val >= min_val) * (val <= max_val)).select(ug.load[nelts](i), 0),
            )

        vectorize[vec_clip_bw, nelts, size = t_shape.num_elements()]()

        return res_grad ^


struct SQUEEZE:
    @staticmethod
    fn result_shape(t1_shape: TensorShape, attributes: AttributeVector) -> TensorShape:
        var dim = attributes["dims"]
        var dims = attributes["dims"]

        if not dim and not dims:
            var new_rank = 0
            for i in range(t1_shape.rank()):
                if t1_shape[i] != 1:
                    new_rank += 1
            var new_shape = List[Int](capacity=new_rank)
            for i in range(t1_shape.rank()):
                if t1_shape[i] != 1:
                    new_shape.append(t1_shape[i])
            return TensorShape(new_shape)
        elif dim:
            var to_remove = dim.value().to_int()
            var new_rank = t1_shape.rank() - 1
            var new_shape = List[Int](capacity=new_rank)
            for i in range(t1_shape.rank()):
                if i != to_remove:
                    new_shape.append(t1_shape[i])
            return TensorShape(new_shape)
        else:
            var to_remove = dims.value().to_shape()
            var new_rank = t1_shape.rank() - to_remove.rank()
            var new_shape = List[Int](capacity=new_rank)
            var j = 0
            for i in range(t1_shape.rank()):
                if j < to_remove.rank() and i == to_remove[j]:
                    j += 1
                else:
                    new_shape.append(t1_shape[i])
            return TensorShape(new_shape)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
        attributes: AttributeVector,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        memcpy(res.data(), t1.data(), t1.num_elements())

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        var res_grad = Tensor[dtype](t1_shape)
        memcpy(res_grad.data(), ug.data(), ug.num_elements())
        return res_grad ^


struct UNSQUEEZE:
    @staticmethod
    fn result_shape(t1_shape: TensorShape, attributes: AttributeVector) -> TensorShape:
        var dim = attributes["dim"]
        var dims = attributes["dims"]

        if not dim and not dims:
            var new_rank = t1_shape.rank() + 1
            var new_shape = List[Int](capacity=new_rank)
            new_shape.append(1)
            for i in range(t1_shape.rank()):
                new_shape.append(t1_shape[i])
            return TensorShape(new_shape)
        elif dim:
            var to_add = dim.value().to_int()
            var new_rank = t1_shape.rank() + 1
            var new_shape = List[Int](capacity=new_rank)
            var j = 0
            for i in range(new_rank):
                if i == to_add:
                    new_shape.append(1)
                else:
                    new_shape.append(t1_shape[j])
                    j += 1
            return TensorShape(new_shape)
        else:
            var to_add = dims.value().to_shape()
            var new_rank = t1_shape.rank() + to_add.rank()
            var new_shape = List[Int](capacity=new_rank)
            var j = 0
            for i in range(new_rank):
                if j < to_add.rank() and i == to_add[j]:
                    new_shape.append(1)
                    j += 1
                else:
                    new_shape.append(t1_shape[i - j])
            return TensorShape(new_shape)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
        attributes: AttributeVector,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        memcpy(res.data(), t1.data(), t1.num_elements())

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        var res_grad = Tensor[dtype](t1_shape)
        memcpy(res_grad.data(), ug.data(), ug.num_elements())
        return res_grad ^


# struct SOFTMAX:
#     @staticmethod
#     fn softmax[axis: Int](n: Tensor[dtype]) -> Tensor[dtype]:
#         """Softmax operation."""
#         # exp(x_i - max(x_j)) / sum(exp(x_j))
#         var max_val = tmax[dtype, nelts](n, axis)
#         var x_minus_max = elwise_op[dtype, nelts, sub](n, max_val)

#         var exp_res = elwise_transform[dtype, nelts, exp](x_minus_max)
#         var sum_res = tsum[dtype, nelts](exp_res, axis)
#         var res = elwise_op[dtype, nelts, div](exp_res, sum_res)

#         return res

#     @staticmethod
#     fn forward[axis: Int](n: Node[dtype]) -> Node[dtype]:
#         """Forward operation of softmax."""
#         # softmax: exp(x_i) / sum(exp(x_j))
#         # stable softmax: exp(x_i - max(x_j)) / sum(exp(x_j))
#         var softmax_res = Self.softmax[axis](n.tensor)
#         var res = elwise_op[dtype, nelts, div](n.tensor, softmax_res)

#         return GRAPH.create_graph_node[Self.backward[axis]](res, n)

#     @staticmethod
#     fn backward[axis: Int](
#         ug: Tensor[dtype], tensor_vec: DynamicVector[String], tensor_id: Int
#     ) -> Tensor[dtype]:
#         """Backward operation of softmax."""
#         pass
