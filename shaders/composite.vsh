#version 460

//attributes
in vec3 vaPosition;
in vec2 vaUV0;

//uniforms
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

uniform vec3 chunkOffset;

uniform int worldTime;

out vec2 texCoord;
flat out int isNight;

void main() {
    texCoord = vaUV0;
    vec4 viewSpacePositionVec4 = modelViewMatrix * vec4(vaPosition+chunkOffset,1);
    
    isNight = 0;  // 白天
    if (worldTime > 12000) {
        isNight = 1;
    }

    gl_Position = projectionMatrix * viewSpacePositionVec4;
}