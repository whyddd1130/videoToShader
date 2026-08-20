#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
uniform int steps;
uniform vec2 stride;

varying vec2 textureCoord;

float getWeight(float x)
{
    return exp(-0.5 * (x * x) / 0.06);
}

void main() 
{
    vec4 total = vec4(0.0);
    float totalWeight = 0.0;
    for (int i = -steps; i <= steps; i++)
    {
        vec2 texCoord = textureCoord + float(i) * stride;
        float weight = getWeight(float(i) / float(steps));
        total += weight * texture2D(inputImageTexture, texCoord);
        totalWeight += weight;
    }

    gl_FragColor = total / vec4(totalWeight);
}
