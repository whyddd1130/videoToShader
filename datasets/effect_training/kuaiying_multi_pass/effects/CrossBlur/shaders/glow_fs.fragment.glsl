#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D blurTex;

uniform float glow_intensity;

void main()
{
    vec2 uv1 = textureCoord;
    vec4 blurCol = texture2D(blurTex, uv1);
    vec4 inputCol = texture2D(inputImageTexture, uv1);

    float grey = dot(blurCol.rgb, vec3(0.299, 0.587, 0.114));
    vec4 res = inputCol + (blurCol * 0.5 + vec4(vec3(grey), blurCol.a) * 0.5) * glow_intensity;
    gl_FragColor = res;
}
