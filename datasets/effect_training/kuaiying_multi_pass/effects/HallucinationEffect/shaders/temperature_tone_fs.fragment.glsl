#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform vec3 u_redVec3;
uniform vec3 u_greenVec3;
uniform vec3 u_blueVec3;

void main()
{
    vec4 src = texture2D(inputImageTexture, textureCoord);
    vec4 outColor = src;
    outColor.r = dot(src.rgb, u_redVec3);
    outColor.g = dot(src.rgb, u_greenVec3);
    outColor.b = dot(src.rgb, u_blueVec3);
    gl_FragColor = clamp(outColor, vec4(0.0), vec4(1.0));
}
