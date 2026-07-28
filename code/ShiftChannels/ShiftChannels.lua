
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

void main() {
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
    //js
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform int channel_r;
uniform int channel_g;
uniform int channel_b;
uniform int channel_a;
uniform int hasPreAlpha;

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float Grayscale(vec3 c)
{
    return 0.299 * c.x + 0.587 * c.y + 0.114 * c.z;
}

void main() {
    vec4 c = texture2D(inputImageTexture, textureCoord);
    float a = c.a + 1e-6;
    c.rgb /= max(a, float(hasPreAlpha));
    c = clamp(c, 0.0, 1.0);

    float grey = Grayscale(c.rgb);
    vec3 hsv = rgb2hsv(c.rgb);

    gl_FragColor = c;

    if (channel_r == 1) {
        gl_FragColor.r = c.a;
    } else if (channel_r == 2) {
        gl_FragColor.r = c.r;
    } else if (channel_r == 3) {
        gl_FragColor.r = c.g;
    } else if (channel_r == 4) {
        gl_FragColor.r = c.b;
    } else if (channel_r == 5) {
        gl_FragColor.r = grey;
    } else if (channel_r == 6) {
        gl_FragColor.r = hsv.x;
    } else if (channel_r == 7) {
        gl_FragColor.r = hsv.z;
    } else if (channel_r == 8) {
        gl_FragColor.r = hsv.y;
    } else if (channel_r == 9) {
        gl_FragColor.r = 1.0;
    } else if (channel_r == 10) {
        gl_FragColor.r = 0.0;
    }

    if (channel_g == 1) {
        gl_FragColor.g = c.a;
    } else if (channel_g == 2) {
        gl_FragColor.g = c.r;
    } else if (channel_g == 3) {
        gl_FragColor.g = c.g;
    } else if (channel_g == 4) {
        gl_FragColor.g = c.b;
    } else if (channel_g == 5) {
        gl_FragColor.g = grey;
    } else if (channel_g == 6) {
        gl_FragColor.g = hsv.x;
    } else if (channel_g == 7) {
        gl_FragColor.g = hsv.z;
    } else if (channel_g == 8) {
        gl_FragColor.g = hsv.y;
    } else if (channel_g == 9) {
        gl_FragColor.g = 1.0;
    } else if (channel_g == 10) {
        gl_FragColor.g = 0.0;
    }

    if (channel_b == 1) {
        gl_FragColor.b = c.a;
    } else if (channel_b == 2) {
        gl_FragColor.b = c.r;
    } else if (channel_b == 3) {
        gl_FragColor.b = c.g;
    } else if (channel_b == 4) {
        gl_FragColor.b = c.b;
    } else if (channel_b == 5) {
        gl_FragColor.b = grey;
    } else if (channel_b == 6) {
        gl_FragColor.b = hsv.x;
    } else if (channel_b == 7) {
        gl_FragColor.b = hsv.z;
    } else if (channel_b == 8) {
        gl_FragColor.b = hsv.y;
    } else if (channel_b == 9) {
        gl_FragColor.b = 1.0;
    } else if (channel_b == 10) {
        gl_FragColor.b = 0.0;
    }

    if (channel_a == 1) {
        gl_FragColor.a = c.a;
    } else if (channel_a == 2) {
        gl_FragColor.a = c.r;
    } else if (channel_a == 3) {
        gl_FragColor.a = c.g;
    } else if (channel_a == 4) {
        gl_FragColor.a = c.b;
    } else if (channel_a == 5) {
        gl_FragColor.a = grey;
    } else if (channel_a == 6) {
        gl_FragColor.a = hsv.x;
    } else if (channel_a == 7) {
        gl_FragColor.a = hsv.z;
    } else if (channel_a == 8) {
        gl_FragColor.a = hsv.y;
    } else if (channel_a == 9) {
        gl_FragColor.a = 1.0;
    } else if (channel_a == 10) {
        gl_FragColor.a = 0.0;
    }

    gl_FragColor.rgb *= gl_FragColor.a;
}
//!js
]]

ShiftChannels = {}

function ShiftChannels:matchWithId(effectId)
    return 'KFM KSkr ShiftChannels' == effectId
end

function ShiftChannels.createWithId(effectId)
    if not ShiftChannels:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, ShiftChannels)
    o:init()
    return o;
end

function ShiftChannels:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShiftChannels:valueType(index)
    if index == 1 then
        -- Channel_A
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        -- Channel_R
        return FM.AEValueType_OneDInt
    elseif index == 3 then
        -- Channel_G
        return FM.AEValueType_OneDInt
    elseif index == 4 then
        -- Channel_B
        return FM.AEValueType_OneDInt
    elseif index == 5 then
        -- hasPreAlpha
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function ShiftChannels:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        -- Channel a
        -- val1 is a index(starts with 1, not 0) of [A | R | G | B | Lumi | Hue | Bri | Sat | 1 | 0]
        program:sendUniformi('channel_a', val1)
    elseif index == 2 then
        -- Channel r
        -- val2 is a index(starts with 1, not 0) of [A | R | G | B | Lumi | Hue | Bri | Sat | 1 | 0]
        program:sendUniformi('channel_r', val1)
    elseif index == 3 then
        -- Channel g
        -- val3 is a index(starts with 1, not 0) of [A | R | G | B | Lumi | Hue | Bri | Sat | 1 | 0]
        program:sendUniformi('channel_g', val1)
    elseif index == 4 then
        -- Channel b
        -- val4 is a index(starts with 1, not 0) of [A | R | G | B | Lumi | Hue | Bri | Sat | 1 | 0]
        program:sendUniformi('channel_b', val1)
    elseif index == 5 then
        -- Channel b
        -- val4 is a index(starts with 1, not 0) of [yes | no]
        program:sendUniformi('hasPreAlpha', val1 - 1)
    end
end

function ShiftChannels:resize(width, height)

end

function ShiftChannels:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function ShiftChannels:onDestroy()
end
    