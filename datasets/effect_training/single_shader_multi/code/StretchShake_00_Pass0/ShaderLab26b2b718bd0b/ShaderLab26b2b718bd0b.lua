
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
uniform sampler2D inputImageTexture;
varying vec2 uv;
#define inputWidth 1080
#define inputHeight 1080
#define iTime uTime
#define lightIns (0.25 + 0.45 * uProgress)
#define moveX (-0.08 + 0.16 * uProgress)
#define moveY (0.08 - 0.16 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
float mirror(float x){
    return abs(mod(x-1.0,2.0)-1.0);
}
vec2 mirror(vec2 uv){
    return vec2(mirror(uv.x),mirror(uv.y));
}
void main()
{
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec4 col = texture2D(inputImageTexture, mirror(uv));
    float gray = dot(col.rgb,vec3(0.299 ,0.587,0.114));
    col.a*=smoothstep(lightIns,lightIns+0.1,gray);
    gl_FragColor = vec4(smoothstep(lightIns,lightIns+0.1,gray));
}

]]

ShaderLab26b2b718bd0b = {}

function ShaderLab26b2b718bd0b:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab26b2b718bd0b' == effectId
end

function ShaderLab26b2b718bd0b.createWithId(effectId)
    if not ShaderLab26b2b718bd0b:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab26b2b718bd0b)
    o:init()
    return o
end

function ShaderLab26b2b718bd0b:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab26b2b718bd0b:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab26b2b718bd0b:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab26b2b718bd0b:resize(width, height)
end

function ShaderLab26b2b718bd0b:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab26b2b718bd0b:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab26b2b718bd0b:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab26b2b718bd0b:onDestroy()
end
