precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;

uniform sampler2D inputImageTexture;
#define u_horz int(8.0 + 112.0 * uProgress)
#define u_vert int(8.0 + 112.0 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
varying vec2 v_uv;

vec4 _f0(float _p0, vec2 _p1, vec2 _p2)
{
    return texture2D(inputImageTexture, _p1 + (_p2 * vec2(_p0, 0.0))) + texture2D(inputImageTexture, _p1 - (_p2 * vec2(_p0, 0.0)));
}

void main()
{
    vec2 _t2 = vec2(float(u_horz), float(u_vert));
    if (u_horz == 0)
    {
        _t2.x = (_t2.y * u_ScreenParams.x) / u_ScreenParams.y;
    }
    else
    {
        if (u_vert == 0)
        {
            _t2.y = (_t2.x * u_ScreenParams.y) / u_ScreenParams.x;
        }
    }
    vec2 _104 = (floor(_t2 * v_uv) + vec2(0.5)) / _t2;
    vec4 _t4 = texture2D(inputImageTexture, _104);
    vec2 _119 = ((vec2(1.0) / _t2) / vec2(4.0)) / vec2(2.0);
    float _t6 = 1.0;
    for (float _t7 = 1.0; _t7 <= 4.0; _t7 += 1.0)
    {
        float param = _t7;
        vec2 param_1 = _104;
        vec2 param_2 = _119;
        vec4 _138 = _t4;
        vec3 _140 = _138.xyz + _f0(param, param_1, param_2).xyz;
        _t4.x = _140.x;
        _t4.y = _140.y;
        _t4.z = _140.z;
        _t6 += 2.0;
    }
    vec4 _153 = _t4;
    vec3 _156 = _153.xyz / vec3(_t6);
    _t4.x = _156.x;
    _t4.y = _156.y;
    _t4.z = _156.z;
    gl_FragColor = _t4;
}

