#version 460

//attributes
in vec3 vaPosition; // 在shadow.vsh中，相对太阳；在gbuffers_whatever.vsh中，相对玩家
in vec2 vaUV0;  // 纹理坐标
in vec4 vaColor;    // 纹理坐标对应的颜色

//uniforms
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform vec3 chunkOffset;

out vec2 texCoord;
out vec3 foliageColor;

void main() {
    texCoord = vaUV0;
    foliageColor = vaColor.rgb;
    vec4 viewSpacePositionVec4 = modelViewMatrix * vec4(vaPosition + chunkOffset, 1);
    gl_Position = projectionMatrix * viewSpacePositionVec4;
}