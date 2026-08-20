
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
basic_vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 v_texCoord;

void main()
{
    v_texCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
hexagon_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;
uniform vec2 u_size;

const float PI = 3.14159265359;
const float TAU = 2.0*PI;
float deg30 = TAU/12.0;

float hexDist(vec2 a, vec2 b)
{
    vec2 p = abs(b-a);
    float s = sin(deg30);
    float c = cos(deg30);
    
    float diagDist = s*p.x + c*p.y;
    return max(diagDist, p.x)/c;
}

vec2 nearestHex(float s, vec2 st)
{
    float h = sin(deg30)*s;
    float r = cos(deg30)*s;
    float b = s + 2.0*h;
    float a = 2.0*r;
    float m = h/r;

    vec2 sect = st/vec2(2.0*r, h+s);
    vec2 sectPxl = mod(st, vec2(2.0*r, h+s));
    
    float aSection = mod(floor(sect.y), 2.0);
    
    vec2 coord = floor(sect);
    if(aSection > 0.0){
        if(sectPxl.y < (h-sectPxl.x*m)){
            coord -= 1.0;
        }
        else if(sectPxl.y < (-h + sectPxl.x*m)){
            coord.y -= 1.0;
        }

    }
    else{
        if(sectPxl.x > r){
            if(sectPxl.y < (2.0*h - sectPxl.x * m)){
                coord.y -= 1.0;
            }
        }
        else{
            if(sectPxl.y < (sectPxl.x*m)){
                coord.y -= 1.0;
            }
            else{
                coord.x -= 1.0;
            }
        }
    }
    
    float xoff = mod(coord.y, 2.0)*r;
    return vec2(coord.x*2.0*r-xoff, coord.y*(h+s))+vec2(r*2.0, s);
}

vec4 processing()
{
    vec2 newUv = vec2(v_texCoord.x * u_size.x, v_texCoord.y * u_size.y);
    float s = u_size.x / 60.0 * (1.0 + u_degree);
    vec2 nearest = nearestHex(s, newUv);
    vec4 texel = texture2D(u_srcSampler, nearest / u_size, -100.0);
    float dist = hexDist(newUv, nearest);
    
    float luminance = (texel.r + texel.g + texel.b) / 3.0;
    float interiorSize = s;
    float interior = 1.0 - smoothstep(interiorSize-1.0, interiorSize, dist);

    return vec4(texel.rgb*interior, texel.a);
}

void main()
{
    gl_FragColor = processing();
}
]]

MosaicHexagon = {}

function MosaicHexagon:matchWithId(effectId)
    return 'KFM KSkr MosaicHexagon' == effectId
end

function MosaicHexagon.createWithId(effectId)
    if not MosaicHexagon:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MosaicHexagon)
    o:init()
    return o;
end

function MosaicHexagon:init()
        self.type = 1
    self.frame = 0
    self.currentWidth = 720
    self.currentHeight = 1280
            self.mTex = 0
    self.mTex1 = 0
    self.mTex2 = 0
    self.mTex3 = 0
    self.currentTime = 0

    self.buffer = {}
    glGenBuffers(1,self.buffer)
    self.vbo = self.buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
    
                    self.program = CGE.ProgramObject()
                self.program:bindAttribLocation('position', 0)
                self.program:initWithShaderStrings(basic_vs, hexagon_fs)
                self.program:bind()
                self.program:sendUniformi("u_srcSampler", 0)
                self.program:sendUniformf("u_degree", 1.0)
                self.program:sendUniformf("u_size", self.currentWidth, self.currentHeight)
end

function MosaicHexagon:valueType(index)
    if index == 1 then
        -- intensity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function MosaicHexagon:updateValue(index, val1, val2, val3)
        if index == 1 then
        -- intensity
        self.program:bind()
        self.program:sendUniformf("u_degree", val1)
    end

end

function MosaicHexagon:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
    self.program:bind()
    self.program:sendUniformf("u_size", width, height)
end

function MosaicHexagon:resize(width, height)

end

function MosaicHexagon:render(outFBO, inputTex)
        local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])
    
            glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
        glViewport(0, 0, self.currentWidth, self.currentHeight)
        self.program:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, inputTex)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    
end


    
function MosaicHexagon:onDestroy()
    if self.mTex ~= 0 then
        glDeleteTextures(1, {self.mTex})
    end
    if self.mTex1 ~= 0 then
        glDeleteTextures(1, {self.mTex1})
    end
    if self.mTex2 ~= 0 then
        glDeleteTextures(1, {self.mTex2})
    end
    if self.mTex3 ~= 0 then
        glDeleteTextures(1, {self.mTex3})
    end
    
    glDeleteBuffers(#self.buffer, self.buffer)
    
    if self.buffers then
        glDeleteBuffers(#self.buffers, self.buffers)
        self.buffers = nil
    end
end
