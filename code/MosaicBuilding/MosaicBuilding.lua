
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
building_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;
uniform vec2 u_size;

float smoothstep_my(float edge0, float edge1, float x)
{
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

vec4 mosaic()
{
    float cx = (0.3 - 0.15 *u_degree) * 100.0;
    float cy = cx * u_size.y / u_size.x;

    vec4 result = texture2D(u_srcSampler, v_texCoord);

    vec2 middle = vec2(floor(v_texCoord.x * cx + 0.5) / cx,floor(v_texCoord.y * cy + 0.5) / cy);
    float dis = abs(distance(vec2(v_texCoord.x*cx,v_texCoord.y*cy),vec2(middle.x*cx,middle.y*cy)) * 2.0 - 0.6);
    
    vec3 color = texture2D(u_srcSampler, middle).rgb;

    // - ： 凸出来
    // + ： 凹进去
    color *= ( - smoothstep_my(0.1,0.05,dis)) * dot(vec2(0.707),normalize(v_texCoord - middle)) * 0.5 + 1.0;

    vec2 delta = vec2(abs(v_texCoord.x - middle.x) * cx * 2.0,abs(v_texCoord.y - middle.y) * cy * 2.0);
    float sdis = max(delta.x,delta.y);

    color *= 0.8 + smoothstep(0.95,0.8,sdis) * 0.2;

    result.rgb = color;

    return result;
}

void main()
{

    gl_FragColor = mosaic();

}
]]

MosaicBuilding = {}

function MosaicBuilding:matchWithId(effectId)
    return 'KFM KSkr MosaicBuilding' == effectId
end

function MosaicBuilding.createWithId(effectId)
    if not MosaicBuilding:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MosaicBuilding)
    o:init()
    return o;
end

function MosaicBuilding:init()
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
                self.program:initWithShaderStrings(basic_vs, building_fs)
                self.program:bind()
                self.program:sendUniformi("u_srcSampler", 0)
                self.program:sendUniformf("u_degree", 1.0)
                self.program:sendUniformf("u_size", self.currentWidth, self.currentHeight)
end

function MosaicBuilding:valueType(index)
    if index == 1 then
        -- intensity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function MosaicBuilding:updateValue(index, val1, val2, val3)
        if index == 1 then
        -- intensity
        self.program:bind()
        self.program:sendUniformf("u_degree", val1)
    end

end

function MosaicBuilding:resize(width, height)

end

function MosaicBuilding:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
    self.program:bind()
    self.program:sendUniformf("u_size", width, height)
end


function MosaicBuilding:render(outFBO, inputTex)
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


    
function MosaicBuilding:onDestroy()
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
    
