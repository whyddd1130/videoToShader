
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


]]

ShaderLab05186308bb2f = {}

function ShaderLab05186308bb2f:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab05186308bb2f' == effectId
end

function ShaderLab05186308bb2f.createWithId(effectId)
    if not ShaderLab05186308bb2f:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab05186308bb2f)
    o:init()
    return o
end

function ShaderLab05186308bb2f:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab05186308bb2f:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab05186308bb2f:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab05186308bb2f:resize(width, height)
end

function ShaderLab05186308bb2f:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab05186308bb2f:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab05186308bb2f:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab05186308bb2f:onDestroy()
end
