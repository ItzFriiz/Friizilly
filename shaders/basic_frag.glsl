#version 460

uniform sampler2D gtexture;

layout(location = 0) out vec4 outColor0;

in vec2 texCoord;

void main() {
    vec4 outputColor = texture(gtexture, texCoord);
    if (outputColor.a < .1) {
        discard;
    }
    outColor0 = texture(gtexture, texCoord);
}