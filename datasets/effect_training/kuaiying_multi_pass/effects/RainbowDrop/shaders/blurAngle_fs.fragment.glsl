#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 screenParams;

mat2 rot2(float angle)
{
    float sinA = sin(angle);
    float cosA = cos(angle);
    return mat2(cosA, -sinA,
                sinA, cosA);
}
vec2 rotUV(vec2 oriUV, mat2 rotAngleMat)
{
    vec2 temp = oriUV - 0.5;
    temp.x *= screenParams.x / screenParams.y;
    temp = temp * rotAngleMat;
    temp.x /= screenParams.x / screenParams.y;
    return temp + 0.5;
    return oriUV;
}

void main()
{
    vec4 col = texture2D(inputImageTexture, textureCoord);
    float num = 1.0;
    float normalAngle = 0.05 * 0.04;
    mat2 rightAngleMat = rot2(normalAngle);
    mat2 leftAngleMat = rot2(-normalAngle);
    vec2 rightUV = textureCoord;
    vec2 leftUV = textureCoord;
    for (int i = 1; i <= 8; i++)
    {
        float j = float(i);
        rightUV = rotUV(rightUV, rightAngleMat);
        vec4 res_r = texture2D(inputImageTexture, rightUV);
        col += res_r;
        leftUV = rotUV(leftUV, leftAngleMat);
        res_r = texture2D(inputImageTexture, leftUV);
        col += res_r;
        num += 2.0;
    }
    col /= num;
    gl_FragColor = col;
}
