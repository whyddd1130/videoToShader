#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;

vec4 gauss()
{
    float u_blur = 0.002 + 0.006 * u_degree;
    vec4 sum = vec4(0.0);
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-4.0*u_blur,0.0)) * 0.05;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-3.0*u_blur,0.0)) * 0.09;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-2.0*u_blur,0.0)) * 0.12;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-1.0*u_blur,0.0)) * 0.15;
    sum += texture2D(u_srcSampler, v_texCoord) * 0.18;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(1.0*u_blur,0.0)) * 0.15;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(2.0*u_blur,0.0)) * 0.12;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(3.0*u_blur,0.0)) * 0.09;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(4.0*u_blur,0.0)) * 0.05;
    return sum;
}

void main()
{
    gl_FragColor = gauss();
}
