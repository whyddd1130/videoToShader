
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
#define u_inverseGammaCorrection 0
#define u_gamma 1.0
#define u_intensity (0.05 + 2.8 * uProgress)
#define u_blurType 1
uniform sampler2D inputImageTexture;
#define u_center vec2(0.5, 0.5)
#define u_quality 0.35
#define u_sampleScale 64.0
#define u_sampleBias 8.0
#define u_weightDecay 0.965
#define u_normalizationSample 64.0
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define u_dither 0.0
#define u_borderType 0
#define u_blurAlpha 1
varying vec2 uv0;

vec4 _f1(mediump sampler2D _p0, vec2 _p1)
{
    vec4 _t0 = texture2D(_p0, _p1);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _75 = _t0;
        vec3 _81 = pow(_75.xyz, vec3(u_gamma));
        _t0.x = _81.x;
        _t0.y = _81.y;
        _t0.z = _81.z;
    }
    return _t0;
}

float _f2(float _p0, inout float _p1, float _p2, float _p3)
{
    _p1 = sign(_p1) * ((0.89999997615814208984375 * abs(_p1)) + 0.100000001490116119384765625);
    return ((_p2 * _p0) * _p1) + _p3;
}

float _f3(float _p0, float _p1, float _p2)
{
    return pow(pow(_p0, _p1), 1.0 / _p2);
}

float _f4(vec2 _p0)
{
    vec2 _126 = fract(_p0 * 13.5170001983642578125);
    vec2 _t1 = _126 + vec2(dot(_126, _126.yx + vec2(22.5410003662109375)));
    return fract((_t1.x + _t1.y) * _t1.y);
}

vec2 _f5(inout vec2 _p0, vec2 _p1, float _p2, float _p3)
{
    float _150 = sin(_p2);
    float _153 = cos(_p2);
    _p0 -= _p1;
    _p0.y /= _p3;
    _p0 = mat2(vec2(_153, _150), vec2(-_150, _153)) * _p0;
    _p0.y *= _p3;
    _p0 += _p1;
    return _p0;
}

float _f0(inout float _p0)
{
    _p0 = abs(_p0);
    return abs((floor(ceil(_p0) / 2.0) * 2.0) - _p0);
}

void main()
{
    float _t4 = u_intensity;
    bool _191 = u_blurType == 4;
    if (_191)
    {
        _t4 *= 0.5;
    }
    vec2 param = uv0;
    vec4 _203 = _f1(inputImageTexture, param);
    vec4 _t5 = _203;
    float _t6 = 1.0;
    float _t7 = 1.0;
    vec4 _t8 = _203 * 1.0;
    float param_1 = u_quality;
    float param_2 = length((uv0 - u_center) * _t4);
    float param_3 = u_sampleScale;
    float param_4 = u_sampleBias;
    float _234 = _f2(param_1, param_2, param_3, param_4);
    float _237 = min(_234, 128.0);
    float _245 = (6.28318500518798828125 * _t4) / _237;
    float param_5 = u_weightDecay;
    float param_6 = u_normalizationSample;
    float param_7 = _237;
    float _255 = _f3(param_5, param_6, param_7);
    float _263 = u_ScreenParams.x / u_ScreenParams.y;
    float _t16 = 0.0;
    if (u_dither > 9.9999997473787516355514526367188e-06)
    {
        vec2 param_8 = vec2(uv0);
        _t16 = (u_dither * ((_f4(param_8) * 2.0) - 1.0)) * _245;
    }
    for (mediump int _t17 = 1; _t17 <= 128; _t17++)
    {
        mediump float _295 = float(_t17);
        if (_295 > _237)
        {
            break;
        }
        _t6 *= _255;
        vec2 param_9 = uv0;
        vec2 param_10 = u_center;
        float param_11 = (_295 * _245) + _t16;
        float param_12 = _263;
        vec2 _318 = _f5(param_9, param_10, param_11, param_12);
        vec2 _t19 = _318;
        bool _321 = _t19.x < 0.0;
        bool _328;
        if (!_321)
        {
            _328 = _t19.y < 0.0;
        }
        else
        {
            _328 = _321;
        }
        bool _335;
        if (!_328)
        {
            _335 = _t19.x > 1.0;
        }
        else
        {
            _335 = _328;
        }
        bool _342;
        if (!_335)
        {
            _342 = _t19.y > 1.0;
        }
        else
        {
            _342 = _335;
        }
        if (_342)
        {
            if (u_borderType == 0)
            {
                _t7 += _t6;
            }
            else
            {
                float param_13 = _t19.x;
                float _358 = _f0(param_13);
                _t19.x = _358;
                float param_14 = _t19.y;
                float _363 = _f0(param_14);
                _t19.y = _363;
                vec2 param_15 = _t19;
                _t8 += (_f1(inputImageTexture, param_15) * _t6);
                _t7 += _t6;
            }
        }
        else
        {
            vec2 param_16 = _t19;
            _t8 += (_f1(inputImageTexture, param_16) * _t6);
            _t7 += _t6;
        }
        if (_191)
        {
            vec2 param_17 = uv0;
            vec2 param_18 = u_center;
            float param_19 = ((-_295) * _245) + _t16;
            float param_20 = _263;
            vec2 _403 = _f5(param_17, param_18, param_19, param_20);
            _t19 = _403;
            bool _406 = _t19.x < 0.0;
            bool _413;
            if (!_406)
            {
                _413 = _t19.y < 0.0;
            }
            else
            {
                _413 = _406;
            }
            bool _420;
            if (!_413)
            {
                _420 = _t19.x > 1.0;
            }
            else
            {
                _420 = _413;
            }
            bool _427;
            if (!_420)
            {
                _427 = _t19.y > 1.0;
            }
            else
            {
                _427 = _420;
            }
            if (_427)
            {
                if (u_borderType == 0)
                {
                    _t7 += _t6;
                }
                else
                {
                    float param_21 = _t19.x;
                    float _441 = _f0(param_21);
                    _t19.x = _441;
                    float param_22 = _t19.y;
                    float _446 = _f0(param_22);
                    _t19.y = _446;
                    vec2 param_23 = _t19;
                    _t8 += (_f1(inputImageTexture, param_23) * _t6);
                    _t7 += _t6;
                }
            }
            else
            {
                vec2 param_24 = _t19;
                _t8 += (_f1(inputImageTexture, param_24) * _t6);
                _t7 += _t6;
            }
        }
    }
    _t8 /= vec4(_t7);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _479 = _t8;
        vec3 _484 = pow(_479.xyz, vec3(1.0 / u_gamma));
        _t8.x = _484.x;
        _t8.y = _484.y;
        _t8.z = _484.z;
    }
    if (u_blurAlpha == 0)
    {
        _t8.w = _t5.w;
    }
    gl_FragColor = _t8;
}


]]

ShaderLab0bd411992637 = {}

function ShaderLab0bd411992637:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab0bd411992637' == effectId
end

function ShaderLab0bd411992637.createWithId(effectId)
    if not ShaderLab0bd411992637:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab0bd411992637)
    o:init()
    return o
end

function ShaderLab0bd411992637:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab0bd411992637:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab0bd411992637:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab0bd411992637:resize(width, height)
end

function ShaderLab0bd411992637:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab0bd411992637:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab0bd411992637:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab0bd411992637:onDestroy()
end
