#version 460

in vec3 vaPosition; // vertex position
in vec2 vaUV0;
in vec4 vaColor;

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

out vec2 texCoord;
out vec3 foliageColor;

void main() {
    texCoord = vaUV0;
    foliageColor = vaColor.rgb;

    gl_Position = projectionMatrix * modelViewMatrix * vec4(vaPosition, 1);
}