
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

#define SIGN(x) (((x) < 0.0) ? -1.0 : 1.0)

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float uExposureIntensity;
uniform float uContrastIntensity;
uniform float uHighlightIntensity;
uniform float uShadowIntensity;
uniform float uWhiteIntensity;
uniform float uBlackIntensity;

vec3 exposureFunc(vec3 a, float b)
{
    return a * pow(2.0, b);
}

vec3 contrastFunc(vec3 a, float b)
{
    float f = b < 0. ? b * .5 : b;
    vec3 e = mix(vec3(.5), a, f);
    vec3 c = 2. * a * e;
    vec3 d = 1. - 2. * (1. - a) * (1. - e);
    a.r = a.r < .5 ? c.r : d.r;
    a.g = a.g <.5 ? c.g : d.g;
    a.b = a.b < .5 ? c.b : d.b;
    return a;
    //return (a - vec3(0.5)) * b + vec3(0.5);
}

vec3 setSat(vec3 c, float s){
    float cmin = min(min(c.r, c.g), c.b);
    float cmax = max(max(c.r, c.g), c.b);

    vec3 res = vec3(0.0);

    if (cmax > cmin) {
        if (c.r == cmin && c.b == cmax) { // R min G mid B max
            res.r = 0.0;
            res.g = ((c.g-cmin)*s) / (cmax-cmin);
            res.b = s;
        }
        else if (c.r == cmin && c.g == cmax) { // R min B mid G max
            res.r = 0.0;
            res.b = ((c.b-cmin)*s) / (cmax-cmin);
            res.g = s;
        }
        else if (c.g == cmin && c.b == cmax) { // G min R mid B max
            res.g = 0.0;
            res.r = ((c.r-cmin)*s) / (cmax-cmin);
            res.b = s;
        }
        else if (c.g == cmin && c.r == cmax) { // G min B mid R max
            res.g = 0.0;
            res.b = ((c.b-cmin)*s) / (cmax-cmin);
            res.r = s;
        }
        else if (c.b == cmin && c.r == cmax) { // B min G mid R max
            res.b = 0.0;
            res.g = ((c.g-cmin)*s) / (cmax-cmin);
            res.r = s;
        }
        else { // B min R mid G max
            res.b = 0.0;
            res.r = ((c.r-cmin)*s) / (cmax-cmin);
            res.g = s;
        }
    }
    return res;
}

vec3 shadows_highlightsFunc(vec3 c, float g)
{
    c += g - dot(c, vec3(0.299, 0.587, 0.114));

    float l = dot(c, vec3(0.299, 0.587, 0.114));
    float n = min(min(c.r, c.g), c.b);
    float x = max(max(c.r, c.g), c.b);
    if (n < 0.0) c = max((c-l)*l / (l-n) + l, 0.0);
    if (x > 1.0) c = min((c-l) * (1.0-l) / (x-l) + l, 1.0);

    return c;
}

vec3 white_blackFunc(vec3 color, float w, float b)
{
    float outBlack = b / 255.0;
    float outWhite = (255.0 + w) / 255.0;
    float diff = outWhite - outBlack;
    color = color * diff + vec3(outBlack);

    return clamp(color, outBlack, outWhite);
}

void main() 
{
    vec4 col = texture2D(inputImageTexture, textureCoord);
    vec3 color = col.rgb;

    if(abs(uExposureIntensity) > 0.0)
    {
        color = exposureFunc(color, uExposureIntensity / 2.0);
    }  
    if(abs(uContrastIntensity) > 0.0)
    {
        color = contrastFunc(color, uContrastIntensity / 100.0);
    }  
    if(abs(uShadowIntensity) > 0.0 || abs(uHighlightIntensity) > 0.0)
    { 
        float gray = dot(color, vec3(0.299, 0.587, 0.114));
        float amt = mix(uHighlightIntensity / 100.0, uShadowIntensity / 100.0, 1.0 - gray) * col.a;
        amt = amt < 0.0 ? amt * 2.0 : amt * 0.9;
        vec3 res = mix(color, vec3(1.0), amt);
        vec3 blend = mix(vec3(1.0), pow(color, vec3(1.0/0.7)), amt);
        res = max(1.0 - ((1.0 - res) / blend), 0.0);

        float gray_res = dot(res, vec3(0.299, 0.587, 0.114));
        float n = min(min(res.r, res.g), res.b);
        float x = max(max(res.r, res.g), res.b);
        color = shadows_highlightsFunc(setSat(color, x-n), gray_res);
    }
    if (abs(uWhiteIntensity) > 0.0 || abs(uBlackIntensity) > 0.0)
    {
        color = white_blackFunc(color, uWhiteIntensity, uBlackIntensity);
    }

    gl_FragColor = vec4(color, col.a);
}
]]

Lumetri = {}

function Lumetri:matchWithId(effectId)
    return 'KFM KSkr Lumetri' == effectId
end

function Lumetri.createWithId(effectId)
    if not Lumetri:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, Lumetri)
    o:init()
    return o;
end

function Lumetri:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function Lumetri:valueType(index)
    if index == 1 then
        -- exposure
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- contrast
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- highlight
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- shadow
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- white
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        -- black
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function Lumetri:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        -- exposure
        program:sendUniformf("uExposureIntensity", val1)
    elseif index == 2 then
        -- contrast
        program:sendUniformf("uContrastIntensity", val1)
    elseif index == 3 then
        -- highlight
        program:sendUniformf("uHighlightIntensity", val1)
    elseif index == 4 then
        -- shadow
        program:sendUniformf("uShadowIntensity", val1)
    elseif index == 5 then
        -- white
        program:sendUniformf("uWhiteIntensity", val1)
    elseif index == 6 then
        -- black
        program:sendUniformf("uBlackIntensity", val1)
    end

end

function Lumetri:resize(width, height)

end

function Lumetri:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function Lumetri:onDestroy()
end
    
