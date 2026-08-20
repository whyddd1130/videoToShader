
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

uniform vec2 screenParams;
uniform vec2 u_center;
uniform float u_angle;
uniform vec3 u_color;
uniform float u_width;
uniform float u_intensity;
uniform int u_blendmode;

const float PI = 3.1415926;
const float c_smoothRange = 0.9;

vec3 blend_screen(vec3 src1, vec3 src2)
{
    return src1 + src2 - src1 * src2;
}

vec3 blend_add(vec3 src1, vec3 src2)
{
    return src1.rgb + src2.rgb;
}

vec3 blend_multiply(vec3 src1, vec3 src2, float alpha)
{
    return src1 * (1.0 - alpha) + src1 * src2;
}

void main() 
{
    vec4 inputColor = texture2D(inputImageTexture, textureCoord);

    float theta = u_angle * PI / 180.0;
    float beta = u_center.y / screenParams.y - tan(theta) * u_center.x /screenParams.x;

    float dist = abs(textureCoord.x * tan(theta) + (-1.0) * textureCoord.y + beta) / sqrt(tan(theta) * tan(theta) + 1.0);

    float u_blackRange = 0.235;
    u_blackRange = u_width;

    float u_blackSmoothRange = 0.3125;

    float blackMask = (1. - smoothstep(0.0 - 0.15, u_width, dist)) * u_intensity;

    vec4 resultColor = inputColor;

    vec4 newColor = vec4(u_color, 1.) * ((1. - smoothstep(u_blackRange, u_blackRange + c_smoothRange, dist)) * u_intensity + 1.);


    if (u_blendmode == 1)
    {
       resultColor = mix(inputColor, newColor * inputColor.a, blackMask);
       gl_FragColor = resultColor;
    }
    if (u_blendmode == 2)
    {
       resultColor.rgb = blend_add(inputColor.rgb, newColor.rgb * inputColor.a * blackMask);
       resultColor.a = inputColor.a;
       gl_FragColor = resultColor;
    }
    if (u_blendmode == 3)
    {
       resultColor = newColor * inputColor.a * blackMask;
       gl_FragColor = resultColor;
    }
    if (u_blendmode == 4)
    {
        resultColor.rgb = blend_screen(inputColor.rgb, newColor.rgb * inputColor.a * blackMask);
        resultColor.a = inputColor.a;
        gl_FragColor = resultColor;
    }
    if (u_blendmode == 5)
    {
        resultColor.rgb = blend_multiply(inputColor.rgb, newColor.rgb * inputColor.a * blackMask, blackMask);
        resultColor.a = inputColor.a;
        gl_FragColor = resultColor;
    }
}
]]

CCLightSweep = {}

function CCLightSweep:matchWithId(effectId)
    return 'KFM KSkr CCLightSweep' == effectId
end

function CCLightSweep.createWithId(effectId)
    if not CCLightSweep:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {},
        currentWidth = 0,
        currentHeight = 0
    }
    o = newObject(o, CCLightSweep)
    o:init()
    return o;
end

function CCLightSweep:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function CCLightSweep:updateValue(index, val1, val2, val3)
    self.program = self.drawer:getProgram()
    self.program:bind()
    if index == 1 then
        -- Center
        self.program:sendUniformf('u_center', val1, val2)
    elseif index == 2 then
        -- Direction
        self.program:sendUniformf('u_angle', val1)
    elseif index == 3 then
        -- Width
        self.program:sendUniformf('u_width', val1 / 100.0 / 2.0)
    elseif index == 4 then
        -- SweepIntensity
        self.program:sendUniformf('u_intensity', val1 / 100.0 * 2.0)
    elseif index == 5 then
        -- LightColor
        self.program:sendUniformf('u_color', val1, val2, val3)
    elseif index == 6 then
        -- LightReception
        -- val1 is a index(starts with 1, not 0) of [Add | Cutout]
        self.program:sendUniformi('u_blendmode', val1)
    end

end

function CCLightSweep:resize(width, height)

end

function CCLightSweep:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height

    self.program:bind()
    self.program:sendUniformf('screenParams', width, height)
end

function CCLightSweep:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function CCLightSweep:onDestroy()
end
    