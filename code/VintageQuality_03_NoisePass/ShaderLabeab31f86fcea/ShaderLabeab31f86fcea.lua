
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
varying vec2 uv;
varying vec2 uv0;
varying vec2 v_uv;
varying vec2 textureCoord;
varying vec2 texCoord;

void main()
{
    vec2 t = position * 0.5 + 0.5;
    uv = t;
    uv0 = t;
    v_uv = t;
    textureCoord = t;
    texCoord = t;
    gl_Position = vec4(position, 0.0, 1.0);
}

]]

local fs = [[
precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;
#define factor1 vec3(0.299, 0.587, 0.114)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define u_scale (0.18 + 1.4 * uProgress)
#define u_scaleR (0.65 + 0.8 * uProgress)
#define u_seed (1.0 + 120.0 * uProgress)
#define u_monochrome 0
#define u_scaleG (0.80 + 0.9 * uProgress)
#define u_scaleB (0.95 + 1.0 * uProgress)
#define u_Brightness (-0.10 + 0.30 * uProgress)
#define u_Contrast (0.65 + 1.60 * uProgress)
#define u_combine 1
#define u_Saturation (0.45 + 1.20 * uProgress)
uniform sampler2D inputImageTexture;
#define u_intensity (0.05 + 2.8 * uProgress)
#define u_intensityR (0.10 + 1.20 * uProgress)
#define u_intensityG (0.10 + 1.00 * uProgress)
#define u_intensityB (0.10 + 0.90 * uProgress)
varying vec2 v_uv;

vec2 _f1(vec2 _p0, float _p1)
{
    vec3 _187 = fract(vec3(_p0.xyx) * vec3(0.103100001811981201171875, 0.10300000011920928955078125, 0.097300000488758087158203125));
    vec3 _200 = _187 + vec3(dot(_187, (_187.yzx + vec3(33.3300018310546875)) + vec3(_p1)));
    return (fract((_200.xx + _200.yz) * _200.zy) * 2.0) - vec2(1.0);
}

float _f2(vec2 _p0, float _p1, float _p2, float _p3)
{
    vec2 _224 = vec2(floor(_p0 / vec2(_p1)));
    vec2 _230 = fract(_p0 / vec2(_p1));
    vec2 _246 = (_230 * _230) * ((_230 * ((_230 * 6.0) - vec2(15.0))) + vec2(10.0));
    vec2 _t11 = mix(_230 * _246, _246, vec2(smoothstep(0.300000011920928955078125, 0.25, _p3)));
    vec2 param = (_224 + vec2(0.0)) * _p1;
    float param_1 = _p2;
    vec2 param_2 = (_224 + vec2(1.0, 0.0)) * _p1;
    float param_3 = _p2;
    vec2 param_4 = (_224 + vec2(0.0, 1.0)) * _p1;
    float param_5 = _p2;
    vec2 param_6 = (_224 + vec2(1.0)) * _p1;
    float param_7 = _p2;
    return mix(mix(dot(_f1(param, param_1), _230 - vec2(0.0)), dot(_f1(param_2, param_3), _230 - vec2(1.0, 0.0)), _t11.x), mix(dot(_f1(param_4, param_5), _230 - vec2(0.0, 1.0)), dot(_f1(param_6, param_7), _230 - vec2(1.0)), _t11.x), _t11.y);
}

float _f3(vec2 _p0, float _p1, float _p2)
{
    float _320 = 2.0 / max(0.100000001490116119384765625, _p1);
    float _326 = floor(_320);
    float _327 = pow(2.0, _326);
    vec2 param = _p0 * 500.0;
    float param_1 = 500.0 / _327;
    float param_2 = _p2;
    float param_3 = _p1;
    float _t13 = (_f2(param, param_1, param_2, param_3) * 0.5) + 0.5;
    vec2 param_4 = _p0 * 300.0;
    float param_5 = 300.0 / _327;
    float param_6 = _p2;
    float param_7 = _p1;
    _t13 = (0.60000002384185791015625 * _t13) + (0.4000000059604644775390625 * ((_f2(param_4, param_5, param_6, param_7) * 0.5) + 0.5));
    float _369 = pow(2.0, _326 + 1.0);
    vec2 param_8 = _p0 * 500.0;
    float param_9 = 500.0 / _369;
    float param_10 = _p2;
    float param_11 = _p1;
    float _t15 = (_f2(param_8, param_9, param_10, param_11) * 0.5) + 0.5;
    vec2 param_12 = _p0 * 300.0;
    float param_13 = 300.0 / _369;
    float param_14 = _p2;
    float param_15 = _p1;
    float _397 = _t15;
    float _401 = (0.60000002384185791015625 * _397) + (0.4000000059604644775390625 * ((_f2(param_12, param_13, param_14, param_15) * 0.5) + 0.5));
    _t15 = _401;
    float _402 = _t13;
    float _406 = mix(_402, _401, fract(_320));
    _t13 = _406;
    return _406;
}

float _f4(inout float _p0, float _p1, float _p2)
{
    _p0 += (_p1 * 0.300000011920928955078125);
    if (_p2 > 0.0)
    {
        _p0 = ((_p0 - 0.5) * ((_p2 * 10.0) + 1.0)) + 0.5;
    }
    else
    {
        _p0 = ((_p0 - 0.5) * (_p2 + 1.0)) + 0.5;
    }
    return _p0;
}

vec4 _f0(vec4 _p0, float _p1)
{
    vec3 _t0 = factor1 / vec3(((factor1.x + factor1.y) + factor1.z) / 0.0199999995529651641845703125);
    float _69 = 50.0 - (_p1 * 100.0);
    mediump vec4 _t2 = _p0;
    mediump vec4 _t3;
    _t3.w = _t2.w;
    vec3 _t4;
    _t4.x = 0.0;
    _t4.y = _t0.x * _69;
    _t4.z = _t0.y * _69;
    vec3 _t5;
    _t5.y = _t4.yz.x;
    _t5.z = _t4.yz.y;
    _t5.x = (1.0 - _t4.z) - _t4.y;
    _t3.x = dot(_p0.xyz, _t5);
    vec3 _t6;
    _t6.y = 0.0;
    _t6.x = _t0.z * _69;
    _t6.z = _t0.y * _69;
    _t5.x = _t6.xz.x;
    _t5.z = _t6.xz.y;
    _t5.y = (1.0 - _t6.x) - _t6.z;
    _t3.y = dot(_p0.xyz, _t5);
    vec3 _t7;
    _t7.z = 0.0;
    _t7.x = _t0.z * _69;
    _t7.y = _t0.x * _69;
    _t5.x = _t7.xy.x;
    _t5.y = _t7.xy.y;
    _t5.z = (1.0 - _t7.x) - _t7.y;
    _t3.z = dot(_p0.xyz, _t5);
    return _t3;
}

void main()
{
    vec2 _t17 = v_uv;
    _t17.x *= (u_ScreenParams.x / u_ScreenParams.y);
    vec2 param = _t17;
    float param_1 = u_scale * u_scaleR;
    float param_2 = u_seed;
    float _463 = _f3(param, param_1, param_2);
    float _t18 = _463;
    float _t19 = _463;
    float _t20 = _463;
    if (u_monochrome == 0)
    {
        vec2 param_3 = _t17;
        float param_4 = u_scale * u_scaleG;
        float param_5 = u_seed + 2.0;
        _t19 = _f3(param_3, param_4, param_5);
        vec2 param_6 = _t17;
        float param_7 = u_scale * u_scaleB;
        float param_8 = u_seed + 4.0;
        _t20 = _f3(param_6, param_7, param_8);
    }
    float param_9 = _t18;
    float param_10 = u_Brightness;
    float param_11 = u_Contrast;
    float _507 = _f4(param_9, param_10, param_11);
    _t18 = _507;
    float param_12 = _t19;
    float param_13 = u_Brightness;
    float param_14 = u_Contrast;
    float _514 = _f4(param_12, param_13, param_14);
    _t19 = _514;
    float param_15 = _t20;
    float param_16 = u_Brightness;
    float param_17 = u_Contrast;
    float _521 = _f4(param_15, param_16, param_17);
    _t20 = _521;
    bool _525 = u_combine == 1;
    bool _528 = u_combine == 2;
    if (_525 || _528)
    {
        _t18 = (_t18 - 0.5) * 2.0;
        _t19 = (_t19 - 0.5) * 2.0;
        _t20 = (_t20 - 0.5) * 2.0;
    }
    else
    {
        if (u_combine == 0)
        {
            _t18 = abs(_t18 - 0.5) * 2.0;
            _t19 = abs(_t19 - 0.5) * 2.0;
            _t20 = abs(_t20 - 0.5) * 2.0;
        }
    }
    vec3 _562 = vec3(_t18, _t19, _t20);
    vec3 _t21 = _562;
    vec4 param_18 = vec4(_562, 1.0);
    float param_19 = u_Saturation;
    _t21 = _f0(param_18, param_19).xyz;
    mediump vec4 _581 = texture2D(inputImageTexture, v_uv);
    vec4 _t22 = _581;
    vec4 _t23;
    if (_525)
    {
        _t23 = vec4(_t21 + _581.xyz, _t22.w);
    }
    else
    {
        if (_528)
        {
            _t23 = vec4(_581.xyz * _t21, _t22.w);
        }
        else
        {
            if (u_combine == 3)
            {
                float _621;
                if (_t22.x < 0.5)
                {
                    _621 = (2.0 * _t22.x) * _t21.x;
                }
                else
                {
                    _621 = 1.0 - ((2.0 * (1.0 - _t22.x)) * (1.0 - _t21.x));
                }
                float _644;
                if (_t22.y < 0.5)
                {
                    _644 = (2.0 * _t22.y) * _t21.y;
                }
                else
                {
                    _644 = 1.0 - ((2.0 * (1.0 - _t22.y)) * (1.0 - _t21.y));
                }
                float _667;
                if (_t22.z < 0.5)
                {
                    _667 = (2.0 * _t22.z) * _t21.z;
                }
                else
                {
                    _667 = 1.0 - ((2.0 * (1.0 - _t22.z)) * (1.0 - _t21.z));
                }
                _t23 = vec4(vec3(_621, _644, _667), _t22.w);
            }
            else
            {
                if (u_combine == 4)
                {
                    float _740;
                    if (_t22.x < 0.5)
                    {
                        _740 = (2.0 * _t22.x) * _t21.x;
                    }
                    else
                    {
                        _740 = 1.0 - ((2.0 * (1.0 - _t22.x)) * (1.0 - _t21.x));
                    }
                    float _763;
                    if (_t22.y < 0.5)
                    {
                        _763 = (2.0 * _t22.y) * _t21.y;
                    }
                    else
                    {
                        _763 = 1.0 - ((2.0 * (1.0 - _t22.y)) * (1.0 - _t21.y));
                    }
                    float _786;
                    if (_t22.z < 0.5)
                    {
                        _786 = (2.0 * _t22.z) * _t21.z;
                    }
                    else
                    {
                        _786 = 1.0 - ((2.0 * (1.0 - _t22.z)) * (1.0 - _t21.z));
                    }
                    vec3 _806 = vec3(_740, _763, _786);
                    _t23 = vec4(mix(_806, vec3(1.0) - ((vec3(1.0) - _806) * (vec3(1.0) - vec3(max(1.0 - ((1.0 - _t21.x) / 0.5), 0.0), max(1.0 - ((1.0 - _t21.y) / 0.5), 0.0), max(1.0 - ((1.0 - _t21.z) / 0.5), 0.0)))), vec3(0.5 * smoothstep(0.588235318660736083984375, 0.509803950786590576171875, dot(_581.xyz, vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625))))), _t22.w);
                }
                else
                {
                    if (u_combine == 5)
                    {
                        _t23 = vec4(abs(_t21 - _581.xyz), _t22.w);
                    }
                    else
                    {
                        _t23 = vec4(vec3(1.0) - ((vec3(1.0) - _581.xyz) * (vec3(1.0) - _t21)), _t22.w);
                    }
                }
            }
        }
    }
    if (_528)
    {
        _t23.x = _t22.x + ((_t23.x * u_intensity) * u_intensityR);
        _t23.y = _t22.y + ((_t23.y * u_intensity) * u_intensityG);
        _t23.z = _t22.z + ((_t23.z * u_intensity) * u_intensityB);
    }
    else
    {
        _t23.x = mix(_t22.x, _t23.x, u_intensity * u_intensityR);
        _t23.y = mix(_t22.y, _t23.y, u_intensity * u_intensityG);
        _t23.z = mix(_t22.z, _t23.z, u_intensity * u_intensityB);
    }
    gl_FragColor = _t23;
}


]]

ShaderLabeab31f86fcea = {}

function ShaderLabeab31f86fcea:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLabeab31f86fcea' == effectId
end

function ShaderLabeab31f86fcea.createWithId(effectId)
    if not ShaderLabeab31f86fcea:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLabeab31f86fcea)
    o:init()
    return o
end

function ShaderLabeab31f86fcea:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLabeab31f86fcea:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLabeab31f86fcea:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLabeab31f86fcea:resize(width, height)
end

function ShaderLabeab31f86fcea:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLabeab31f86fcea:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLabeab31f86fcea:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLabeab31f86fcea:onDestroy()
end
