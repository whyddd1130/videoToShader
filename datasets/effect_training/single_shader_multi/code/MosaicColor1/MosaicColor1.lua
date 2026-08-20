
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
color_1_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;
uniform vec2 u_size;

const float min_scale = 10.0;
const float max_scale = 200.0;

vec2 random2(vec2 p) {
  return fract(
      sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) *
      43758.5453);
}

float pseudoRandom(vec2 st) {
  return fract(sin(dot(st, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 processing() {
  float scale = min_scale + (max_scale - min_scale) * (0.25 - 0.25 * u_degree);

  vec2 st = v_texCoord;
  st.x *= u_size.x / u_size.y;

  st *= scale;

  vec2 i_st = floor(st);
  vec2 f_st = fract(st);
  float m_dist = 100.;
  vec2 uv = st;
  bool tag = false;
  for (int y = -1; y <= 1; ++y) {
    for (int x = -1; x <= 1; ++x) {
      vec2 neighbor = vec2(float(x), float(y));
      vec2 point = random2(i_st + neighbor);
      point = 0.5 + 0.5 * sin((0.25 - 0.25 * u_degree) + 6.2831 * point);
      vec2 diff = neighbor + point - f_st;
      float dist = length(diff);

      if (dist < 0.8 && m_dist > dist) {
        m_dist = dist;
        uv = st + diff;
        tag = true;
      }
    }
  }

  if (!tag) {
    float offsetR = random2(v_texCoord).x;
    float offsetG = random2(v_texCoord * 1.2345).x;
    float offsetB = random2(v_texCoord * 3.4567).x;

    // 应用随机偏移
    vec3 newColor = vec3(1.0) + vec3(offsetR, offsetG, offsetB) * 0.3;
    gl_FragColor = vec4(newColor, 1.0);
    return vec4(1.0) * texture2D(u_srcSampler, v_texCoord).a;
  }

  uv /= scale;
  uv.x /= u_size.x / u_size.y;
  float alpha = texture2D(u_srcSampler, uv).a;
  vec3 color = texture2D(u_srcSampler, uv).rgb;

  if (alpha > 0.0) {
    color /= alpha;
  }

  vec2 testUv = vec2(uv.x * 10000.0, uv.y * 10000.0);
  testUv = vec2(floor(testUv.x) / 10000.0, floor(testUv.y) / 10000.0);

  float offsetR = random2(testUv).x;
  float offsetG = random2(testUv * 1.2345).x;
  float offsetB = random2(testUv * 3.4567).x;

  // 应用随机偏移
  vec3 newColor = color.rgb + vec3(offsetR, offsetG, offsetB) * 0.3;

  color = newColor;

  return vec4(color, 1.0) * alpha;
}

void main() {
    gl_FragColor = processing();
}
]]

MosaicColor1 = {}

function MosaicColor1:matchWithId(effectId)
    return 'KFM KSkr MosaicColor1' == effectId
end

function MosaicColor1.createWithId(effectId)
    if not MosaicColor1:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MosaicColor1)
    o:init()
    return o;
end

function MosaicColor1:init()
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
                self.program:initWithShaderStrings(basic_vs, color_1_fs)
                self.program:bind()
                self.program:sendUniformi("u_srcSampler", 0)
                self.program:sendUniformf("u_degree", 1.0)
                self.program:sendUniformf("u_size", self.currentWidth, self.currentHeight)
end

function MosaicColor1:valueType(index)
    if index == 1 then
        -- intensity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function MosaicColor1:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
    self.program:bind()
    self.program:sendUniformf("u_size", width, height)
end

function MosaicColor1:updateValue(index, val1, val2, val3)
        if index == 1 then
        -- intensity
        self.program:bind()
        self.program:sendUniformf("u_degree", val1)
    end

end

function MosaicColor1:resize(width, height)

end

function MosaicColor1:render(outFBO, inputTex)
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
    

function MosaicColor1:onDestroy()
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
