
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float curTime;
uniform float speed;
uniform int samples;

#define SAMPLES_F float(samples)

#define TAU  6.28318530718
float random(vec3 p3)
{
	p3  = fract(p3 * 100.);
    p3 += dot(p3, p3.yzx + 11.);
    return fract((p3.x + p3.y) * p3.z);
}

void main() 
{
    vec2 uv = textureCoord;
    vec4 color = vec4(0.0, 0.0, 0.0, 0.0);
    float r = 0.05 + 0.05 * sin(curTime*speed*TAU+14.3);

    for (int i = 0; i < samples; ++i)
    {
        float fi = float(i);
        float rnd = random(vec3(uv.xy, fi));
        float f = (fi + rnd) / SAMPLES_F;
        f = (f * 2.0 - 1.0) * r;

        color = max(texture2D(inputImageTexture, uv + vec2(f, 0.0)) , color);
    }


    gl_FragColor = color;
}
]]

MotionBlur = {}

function MotionBlur:matchWithId(effectId)
    return 'KFM KSkr motionBlur' == effectId
end

function MotionBlur.createWithId(effectId)
    if not MotionBlur:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MotionBlur)
    o:init()
    return o;
end

function MotionBlur:updateTimeAndFrame(time, frame)
    self.currentTime = time
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("curTime", self.currentTime)
end

function MotionBlur:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function MotionBlur:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function MotionBlur:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        program:sendUniformf("speed", val1)
    elseif index == 2 then
        program:sendUniformi("samples", val1)
    end
end

function MotionBlur:resize(width, height)

end

function MotionBlur:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function MotionBlur:onDestroy()
end
    