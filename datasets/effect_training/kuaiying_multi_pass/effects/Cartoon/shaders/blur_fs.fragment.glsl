#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

#define spatialWeight 10.0
#define tonalWeight 0.1
#define PI 3.141592
#define TAU (PI * 2.0)

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform vec2 imageSize;
uniform float detailRadius;
uniform float detailThreshold;
uniform int direction;

float Gaussian(float d, float sigma) 
{
    return 1.0 / (sigma * sqrt(TAU)) * exp(-(d * d) / (2.0 * sigma * sigma));
}

vec4 Gaussian(vec4 d, float sigma) 
{
    return 1.0 / (sigma * sqrt(TAU)) * exp(-(d * d) / (2.0 * sigma * sigma));
}

vec4 WeightFunction(vec2 s, vec2 s0) 
{
    float spacialDifference = length(s - s0); //空间距离
    vec4 tonalDifference = texture2D(inputImageTexture, s) - texture2D(inputImageTexture, s0); //像素距离

    float tonalDifferenceIntensity = 0.2126 * tonalDifference.r + 0.7152 * tonalDifference.g + 0.0722 * tonalDifference.b;
    return Gaussian(spacialDifference, spatialWeight) * Gaussian(vec4(vec3(tonalDifferenceIntensity), tonalDifference.a), tonalWeight * detailThreshold);
}

void main() 
{
    vec4 numerator = vec4(0.0);  
    vec4 denominator = vec4(0.0); 

    if(direction == 1)
    {
        for (int k = 0; k < int(detailRadius) * 2 + 1; k++) 
        {
            vec2 idOffset = vec2(textureCoord.x, textureCoord.y + (float(k) - detailRadius) / imageSize.y);

            if (idOffset.y >= 0.0 && idOffset.y < 1.0) 
            {
                vec4 weight = WeightFunction(idOffset, textureCoord);
                numerator += texture2D(inputImageTexture, idOffset) * weight;
                denominator += weight;
            }
        }
    }
    if(direction == 2)
    {
        for (int k = 0; k < int(detailRadius) * 2 + 1; k++) 
        {
            vec2 idOffset = vec2(textureCoord.x + (float(k) - detailRadius) / imageSize.x, textureCoord.y);

            if (idOffset.x >= 0.0 && idOffset.x < 1.0) 
            {
                vec4 weight = WeightFunction(idOffset, textureCoord);
                numerator += texture2D(inputImageTexture, idOffset) * weight;
                denominator += weight;
            }
        }
    }
    gl_FragColor = numerator / denominator;
}
