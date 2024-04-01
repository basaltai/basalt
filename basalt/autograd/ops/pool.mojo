from math.limit import neginf

from basalt import Tensor, TensorShape
from basalt.autograd.attributes import AttributeVector
from basalt.autograd.ops.conv import get_result_shape


@register_passable("trivial")
struct Maxpool_2D:
    @staticmethod
    @always_inline("nodebug")
    fn result_shape(
        input_shape: TensorShape, attributes: AttributeVector
    ) -> TensorShape:
        var kernel_size = attributes["kernel_size"].value().to_static[2]()
        var padding = attributes["padding"].value().to_static[2]()
        var stride = attributes["stride"].value().to_static[2]()
        var dilation = attributes["dilation"].value().to_static[2]()

        var res = get_result_shape(
            input_shape,
            TensorShape(kernel_size[0], kernel_size[1]),
            padding,
            stride,
            dilation,
        )

        return TensorShape(input_shape[0], input_shape[1], res[0], res[1])

    @staticmethod
    @always_inline("nodebug")
    fn forward[
        InputShape: TensorShape, Attributes: AttributeVector
    ](inout outputs: Tensor[dtype], inputs: Tensor[dtype]):
        """
        Returns the max value of each kernel in the input tensor.
            inputs.shape     [batch_size, channels, iX, iY]
            with kernel_size = (kX, kY)
            outputs.shape    [batch_size, channels, oX, oY].
        """
        alias kernel_size = Attributes["kernel_size"].value().to_static[2]()
        alias padding = Attributes["padding"].value().to_static[2]()
        alias stride = Attributes["stride"].value().to_static[2]()
        alias dilation = Attributes["dilation"].value().to_static[2]()

        alias inputs_strides = InputShape.strides()
        alias output_shape = Self.result_shape(InputShape, Attributes)
        alias outputs_strides = output_shape.strides()

        for batch in range(InputShape[0]):
            for in_ch in range(InputShape[1]):
                for x in range(output_shape[2]):
                    for y in range(output_shape[3]):
                        var max_val: SIMD[dtype, 1] = neginf[dtype]()
                        var ix_base = x * stride[0] - padding[0]
                        var iy_base = y * stride[1] - padding[1]
                        for kx in range(kernel_size[0]):
                            for ky in range(kernel_size[1]):
                                var ix = ix_base + kx * dilation[0]
                                var iy = iy_base + ky * dilation[1]

                                if (
                                    ix < 0
                                    or iy < 0
                                    or ix >= InputShape[2]
                                    or iy >= InputShape[3]
                                ):
                                    continue

                                var idx = (
                                    batch * inputs_strides[0]
                                    + in_ch * inputs_strides[1]
                                    + ix * inputs_strides[2]
                                    + iy
                                )

                                var val = inputs[idx]
                                if val > max_val:
                                    max_val = val

                        var out_idx = (
                            batch * outputs_strides[0]
                            + in_ch * outputs_strides[1]
                            + x * outputs_strides[2]
                            + y
                        )

                        outputs[out_idx] = max_val

    @staticmethod
    @always_inline("nodebug")
    fn backward[
        UGShape: TensorShape, InputShape: TensorShape, Attributes: AttributeVector
    ](ug: Tensor[dtype], inputs: Tensor[dtype]) -> Tensor[dtype]:
        """
        Backward operation of MAXPOOL2D.

        Upper gradient of shape: [batch_size, channels, uX, uY]
        """
        alias kernel_size = Attributes["kernel_size"].value().to_static[2]()
        alias padding = Attributes["padding"].value().to_static[2]()
        alias stride = Attributes["stride"].value().to_static[2]()
        alias dilation = Attributes["dilation"].value().to_static[2]()

        alias ug_strides = UGShape.strides()
        alias inputs_strides = InputShape.strides()

        var res = Tensor[dtype](InputShape)

        for batch in range(InputShape[0]):
            for in_ch in range(InputShape[1]):
                for x in range(UGShape[2]):
                    for y in range(UGShape[3]):
                        var max_val: SIMD[dtype, 1] = neginf[dtype]()
                        var max_idx: Int = -1
                        var ix_base = x * stride[0] - padding[0]
                        var iy_base = y * stride[1] - padding[1]
                        for kx in range(kernel_size[0]):
                            for ky in range(kernel_size[1]):
                                var ix = ix_base + kx * dilation[0]
                                var iy = iy_base + ky * dilation[1]

                                if (
                                    ix < 0
                                    or iy < 0
                                    or ix >= InputShape[2]
                                    or iy >= InputShape[3]
                                ):
                                    continue

                                var idx = (
                                    batch * inputs_strides[0]
                                    + in_ch * inputs_strides[1]
                                    + ix * inputs_strides[2]
                                    + iy
                                )

                                var val = inputs[idx]
                                if val > max_val:
                                    max_val = val
                                    max_idx = idx

                        var ug_idx = (
                            batch * ug_strides[0]
                            + in_ch * ug_strides[1]
                            + x * ug_strides[2]
                            + y
                        )

                        res[max_idx] += ug[ug_idx]

        return res
