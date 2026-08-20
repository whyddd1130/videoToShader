
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
varying vec2 textureCoordinate;
varying vec2 uRenderSize;

void main()
{
    vec2 t = position * 0.5 + 0.5;
    uv = t;
    uv0 = t;
    v_uv = t;
    textureCoord = t;
    texCoord = t;
    textureCoordinate = t;
    uRenderSize = vec2(1080.0, 1080.0);
    gl_Position = vec4(position, 0.0, 1.0);
}

]]

local fs = [[
precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define u_axisFrag 0
#define u_warpStyleFrag 0
#define u_bend (0.02 + 0.80 * uProgress)
uniform sampler2D inputImageTexture;

varying vec2 v_uv;

vec2 _f3(vec2 _p0, inout float _p1, mediump int _p2)
{
    if (_p2 != 0)
    {
        _p1 *= (-1.0);
    }
    vec2 _t1 = _p0;
    float _80 = (1.0 / pow(clamp(abs(_p1), 9.9999997473787516355514526367188e-06, 1.0), 0.569999992847442626953125)) - 1.0;
    _t1.x -= 0.5;
    if (_p1 < 0.0)
    {
        _t1.y = 1.0 - _t1.y;
    }
    _t1.y += _80;
    float _107 = _t1.y;
    float _109 = _t1.x;
    float _114 = atan(0.5, _80);
    _t1.y = (length(_t1) - (sqrt(0.25 + (_80 * _80)) - _80)) - _80;
    if (_p1 < 0.0)
    {
        _t1.y = 1.0 - _t1.y;
    }
    _t1.x = 1.0 - ((atan(_107, _109) - (1.57079637050628662109375 - _114)) / (_114 * 2.0));
    if (_p2 == 0)
    {
        return _t1;
    }
    else
    {
        return vec2(_t1.y, _t1.x);
    }
}

vec2 _f0(vec2 _p0)
{
    return vec2(1.0) - _p0;
}

float _f1(float _p0)
{
    return _p0 * _p0;
}

float _f2(float _p0)
{
    return (_p0 * _p0) * _p0;
}

vec2 _f4(vec2 _p0, float _p1, mediump int _p2, bool _p3)
{
    float _172 = u_ScreenParams.x / u_ScreenParams.y;
    vec2 _t7 = _p0;
    if (_p3)
    {
        vec2 param = _t7;
        _t7 = _f0(param);
    }
    float _184 = _t7.x - 0.5;
    float _191 = (1.0 / pow(clamp(abs(_p1), 9.9999997473787516355514526367188e-06, 1.0), 0.569999992847442626953125)) - 1.0;
    float param_1 = _191;
    float _198 = sqrt(_f1(param_1) + 0.25);
    float param_2 = _198;
    float param_3 = _184;
    float _t11 = ((sqrt(_f1(param_2) - _f1(param_3)) - _191) * _172) + 1.0;
    if (_p1 < 0.0)
    {
        float param_4 = _198;
        float param_5 = _184;
        _t11 = 1.0 - ((sqrt(_f1(param_4) - _f1(param_5)) - _191) * _172);
    }
    _t7.y /= _t11;
    _t7.x -= 0.5;
    float param_6 = abs((abs(_t7.x) * 2.0) - 0.5);
    _t7.x *= mix(1.0, (_f2(param_6) * 2.0) + 0.75, _t7.y * clamp(abs(_p1), 0.0, 1.0));
    _t7.x += 0.5;
    if (_p3)
    {
        vec2 param_7 = _t7;
        _t7 = _f0(param_7);
    }
    if (_p2 != 0)
    {
        return vec2(_t7.y, _t7.x);
    }
    return _t7;
}

float _f5(vec2 _p0)
{
    vec2 _t13 = step(vec2(0.0), _p0) * step(_p0, vec2(1.0));
    return _t13.x * _t13.y;
}

void main()
{
    vec2 _t14 = v_uv;
    bool _308 = u_axisFrag == 0;
    float _t15;
    float _t16;
    if (_308)
    {
        _t15 = _t14.x;
        _t16 = _t14.y;
    }
    else
    {
        _t15 = _t14.y;
        _t16 = _t14.x;
    }
    vec2 _325 = vec2(_t15, _t16);
    if (u_warpStyleFrag == 0)
    {
        vec2 param = _325;
        float param_1 = u_bend;
        mediump int param_2 = u_axisFrag;
        vec2 _338 = _f3(param, param_1, param_2);
        _t14 = _338;
    }
    else
    {
        if (u_warpStyleFrag == 1)
        {
            vec2 param_3 = _325;
            float param_4 = u_bend;
            mediump int param_5 = u_axisFrag;
            bool param_6 = _308;
            _t14 = _f4(param_3, param_4, param_5, param_6);
        }
        else
        {
            if (u_warpStyleFrag == 2)
            {
                vec2 param_7 = _325;
                float param_8 = u_bend;
                mediump int param_9 = u_axisFrag;
                bool param_10 = u_axisFrag != 0;
                _t14 = _f4(param_7, param_8, param_9, param_10);
            }
            else
            {
                if (u_warpStyleFrag == 5)
                {
                    _t14.x = 1.0 - _t14.x;
                    if (u_bend > 0.0)
                    {
                        if (_308)
                        {
                            _t14.y = 1.0 - _t14.y;
                        }
                        else
                        {
                            if (u_axisFrag == 1)
                            {
                                _t14.x = 1.0 - _t14.x;
                            }
                        }
                    }
                }
                else
                {
                    if (u_warpStyleFrag == 6)
                    {
                        if (_308 && (u_bend <= 0.0))
                        {
                            _t14.y = 1.0 - _t14.y;
                        }
                        if (u_axisFrag == 1)
                        {
                            _t14.y = 1.0 - _t14.y;
                            if (u_bend > 0.0)
                            {
                                _t14.x = 1.0 - _t14.x;
                            }
                        }
                    }
                }
            }
        }
    }
    vec2 param_11 = _t14;
    gl_FragColor = texture2D(inputImageTexture, _t14) * _f5(param_11);
}


]]

ShaderLab25034455c646 = {}

function ShaderLab25034455c646:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab25034455c646' == effectId
end

function ShaderLab25034455c646.createWithId(effectId)
    if not ShaderLab25034455c646:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab25034455c646)
    o:init()
    return o
end

function ShaderLab25034455c646:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab25034455c646:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab25034455c646:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab25034455c646:resize(width, height)
end

function ShaderLab25034455c646:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab25034455c646:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab25034455c646:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab25034455c646:onDestroy()
end
