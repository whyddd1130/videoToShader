#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float blurSize;

void main()
{
    vec2 uv1 = textureCoord;
    vec4 col = vec4(0.0);
    float num = 0.0;
    for (int i = 1; i <= 8; i++)
    {
        float j = float(i);
        vec2 tempUV = (uv1 - 0.5) / mix(1.0, blurSize, j / 8.) + 0.5;
        vec4 res_r = texture2D(inputImageTexture, tempUV);
        col += res_r;
        tempUV = (uv1 - 0.5) * mix(1.0, blurSize, j / 8.) + 0.5;
        res_r = texture2D(inputImageTexture, tempUV);
        col += res_r;
        num += 2.0;
    }
    col /= num;
    gl_FragColor = col;
}
