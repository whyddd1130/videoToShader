#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
uniform float exposure;
uniform int blendMode;

varying vec2 textureCoord;

void main() 
{
    vec4 resColor = texture2D(inputImageTexture, textureCoord);
    resColor.a = min(resColor.a, 1.0);

    if (blendMode == 1)
    {
        resColor.rgb *= vec3(exposure);
    }

   // if (gammaCorrect == 1)
   // {
   //     resColor.rgb = pow(resColor.rgb, vec3(0.45454545));
   // }

    resColor.a = min(resColor.a, 1.0);

    if (blendMode == 1)
    {
        resColor.rgb = min(resColor.rgb, 1.0);
    }

    gl_FragColor = resColor;
}
