
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
varying highp vec2 uv0;
uniform sampler2D inputImageTexture;
#define u_Strength (20.0 + 180.0 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define centerX 540.0
#define centerY 540.0
float uvProtect(vec2 uv)
{
    return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}
float mirror(float x){
    return abs(mod(x-1.0,2.0)-1.0);
}
vec2 mirror(vec2 uv){
    return vec2(mirror(uv.x),mirror(uv.y));
}
void main()
{

    vec2 uv = (uv0-0.5)*1.1+0.5;
    vec2 ratio = (u_ScreenParams.xy / max(u_ScreenParams.x, u_ScreenParams.y));
    vec2 center = vec2(centerX/1080.,centerY/1920.);
    for (int i = 1; i < 16; ++i)
    {
        uv -= center;
        uv *= ratio;
        float d = length(uv * 2.0);
        uv = uv * pow((d*d) + 1.0, -pow(u_Strength * 0.0059375, 3.0));
        uv /= ratio;

        uv += center;
    }
    gl_FragColor = texture2D(inputImageTexture, mirror(uv)) ;
}
]]

ShaderLab3870310ee55a = {}

function ShaderLab3870310ee55a:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab3870310ee55a' == effectId
end

function ShaderLab3870310ee55a.createWithId(effectId)
    if not ShaderLab3870310ee55a:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab3870310ee55a)
    o:init()
    return o
end

function ShaderLab3870310ee55a:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab3870310ee55a:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab3870310ee55a:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab3870310ee55a:resize(width, height)
end

function ShaderLab3870310ee55a:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab3870310ee55a:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab3870310ee55a:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab3870310ee55a:onDestroy()
end
