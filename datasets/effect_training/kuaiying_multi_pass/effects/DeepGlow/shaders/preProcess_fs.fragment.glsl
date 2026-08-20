#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
uniform float threshold;
uniform float thresholdSmooth;
uniform float exposure;
uniform int blendMode;

varying vec2 textureCoord;

void main() 
{
    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    oriColor.rgb *= vec3(oriColor.a);
    // oriColor.a = 1.0;
    oriColor = max(oriColor, vec4(0.0));

    float thresholdPercent = 0.0;
    // if (isThreshold == 1)
    if (true) 
    {
        if (oriColor.r < threshold)
        {
            thresholdPercent = oriColor.r / threshold;
            oriColor.r = ((thresholdPercent * oriColor.r) * thresholdSmooth);
        }
        if (oriColor.g < threshold)
        {
            thresholdPercent = oriColor.g / threshold;
            oriColor.g = ((thresholdPercent * oriColor.g) * thresholdSmooth);
        }
        if (oriColor.b < threshold)
        {
            thresholdPercent = oriColor.b / threshold;
            oriColor.b = ((thresholdPercent * oriColor.b) * thresholdSmooth);
        }
    }

   // if (gammaCorrect == 1)
   // {
   //     oriColor.rgb = pow(oriColor.rgb, vec3(2.222222));
   // }
    if (blendMode == 1)
    {
        oriColor = min(oriColor, vec4(1.0));   // if screen, clamp all values at 1.0 and do exposure as post process
    }
    else
    {
        oriColor.rgb *= vec3(exposure);
    }

    gl_FragColor = oriColor;
}
