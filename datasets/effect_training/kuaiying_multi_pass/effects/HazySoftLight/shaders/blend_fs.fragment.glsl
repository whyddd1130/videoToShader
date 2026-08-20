#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform mediump sampler2D u_glowTexture;

uniform float u_exposure;
uniform mediump int u_displayGlow;

vec4 _f0(vec4 _p0, vec4 _p1)
{
    return (_p0 + _p1) - (_p0 * _p1);
}

void main()
{
    mediump vec4 _33 = texture2D(inputImageTexture, textureCoord);
    vec4 _t1 = vec4(0.0);
    if (u_exposure > 0.001)
    {
        _t1 = texture2D(u_glowTexture, textureCoord);
    }
    vec4 _53 = _t1;
    vec3 _55 = _53.xyz * vec3(1.0, 1.0, 1.0);
    _t1.x = _55.x;
    _t1.y = _55.y;
    _t1.z = _55.z;
    vec4 param = _t1;
    vec4 param_1 = _33;
    if (u_displayGlow == 1)
    {
        gl_FragColor = clamp(_t1, vec4(0.0), vec4(1.0));
    }
    else
    {
        gl_FragColor = clamp(_f0(param, param_1), vec4(0.0), vec4(1.0));
    }
}
