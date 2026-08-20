precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;

uniform sampler2D inputImageTexture;
#define u_horz int(8.0 + 112.0 * uProgress)
#define u_vert int(8.0 + 112.0 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define u_sharp 0
varying vec2 v_uv;

vec4 _f0(float _p0, vec2 _p1, vec2 _p2)
{
    return texture2D(inputImageTexture, _p1 + (_p2 * vec2(0.0, _p0))) + texture2D(inputImageTexture, _p1 - (_p2 * vec2(0.0, _p0)));
}

void main()
{
    bool _54 = u_horz == 0;
    bool _57 = u_vert == 0;
    if (_54 && _57)
    {
        gl_FragColor = texture2D(inputImageTexture, v_uv);
        return;
    }
    vec2 _t2 = vec2(float(u_horz), float(u_vert));
    if (_54)
    {
        _t2.x = (_t2.y * u_ScreenParams.x) / u_ScreenParams.y;
    }
    else
    {
        if (_57)
        {
            _t2.y = (_t2.x * u_ScreenParams.y) / u_ScreenParams.x;
        }
    }
    vec4 _t4;
    if (u_sharp == 1)
    {
        _t4 = texture2D(inputImageTexture, floor(_t2 * v_uv) / _t2);
    }
    else
    {
        vec2 _135 = (floor(_t2 * v_uv) + vec2(0.5)) / _t2;
        _t4 = texture2D(inputImageTexture, _135);
        vec2 _149 = ((vec2(1.0) / _t2) / vec2(4.0)) / vec2(2.0);
        float _t7 = 1.0;
        for (float _t8 = 1.0; _t8 <= 4.0; _t8 += 1.0)
        {
            float param = _t8;
            vec2 param_1 = _135;
            vec2 param_2 = _149;
            vec4 _168 = _t4;
            vec3 _170 = _168.xyz + _f0(param, param_1, param_2).xyz;
            _t4.x = _170.x;
            _t4.y = _170.y;
            _t4.z = _170.z;
            _t7 += 2.0;
        }
        vec4 _183 = _t4;
        vec3 _186 = _183.xyz / vec3(_t7);
        _t4.x = _186.x;
        _t4.y = _186.y;
        _t4.z = _186.z;
    }
    gl_FragColor = _t4;
}

