//
//  YUVDisplayGLViewController.m
//  rtsp_player
//
//  Created by J.C. Li on 11/17/12.
//  Copyright (c) 2012 J.C. Li. All rights reserved.
//

#import "YUVDisplayGLViewController.h"
#import <QuartzCore/QuartzCore.h>
#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

typedef struct {
    float Position[3];
    float Color[4];
    float TexCoord[2];
} Vertex;

const Vertex Vertices[] = {
    {{1, -1, 0}, {1, 1, 1, 1}, {0, 1}},
    {{1, 1, 0}, {1, 1, 1, 1}, {0, 0}},
    {{-1, 1, 0}, {1, 1, 1, 1}, {1, 0}},
    {{-1, -1, 0}, {1, 1, 1, 1}, {1, 1}}
};

const GLubyte Indices[] = {
    0, 1, 2,
    2, 3, 0
};

#pragma mark - shaders

#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)

NSString *const vertexShaderString = SHADER_STRING
(
 attribute vec4 Position; // 1
 attribute vec4 SourceColor; // 2
 
 varying vec4 DestinationColor; // 3
 
 attribute vec2 TexCoordIn;
 varying vec2 TexCoordOut;
 
 void main(void) { // 4
     DestinationColor = SourceColor; // 5
     gl_Position = Position; // 6
     TexCoordOut = TexCoordIn; // New

 }
);

NSString *const rgbFragmentShaderString = SHADER_STRING
(
// varying lowp vec4 DestinationColor; // 1
// 
// varying lowp vec2 TexCoordOut;
// uniform sampler2D Texture;
// 
// void main(void) { // 2
//     gl_FragColor = DestinationColor  * texture2D(Texture, TexCoordOut);
// }
 
 varying highp vec2 TexCoordOut;
 uniform sampler2D s_texture_y;
 uniform sampler2D s_texture_u;
 uniform sampler2D s_texture_v;
 
 void main()
 {
     highp float y = texture2D(s_texture_y, TexCoordOut).r;
     highp float u = texture2D(s_texture_u, TexCoordOut).r - 0.5;
     highp float v = texture2D(s_texture_v, TexCoordOut).r - 0.5;
//     highp float u = texture2D(s_texture_u, TexCoordOut).r;
//     highp float v = texture2D(s_texture_v, TexCoordOut).r;
//     highp float u = 1.0;
//     highp float v = 1.0;
     
     highp float r = y +             1.402 * v;
     highp float g = y - 0.344 * u - 0.714 * v;
     highp float b = y + 1.772 * u;
//     highp float r = y;
//     highp float g = 0.0;
//     highp float b = 0.0;
     
     gl_FragColor = vec4(r,g,b,1.0);
 }
 
);


#pragma mark - YUVDisplayGLViewController implementation

@interface YUVDisplayGLViewController(){
    float _curRed;
    BOOL _increasing;
    
    GLuint _vertexBuffer;
    GLuint _indexBuffer;
    
    GLuint _positionSlot;
    GLuint _colorSlot;
    
    GLuint _yTexture;
    GLuint _uTexture;
    GLuint _vTexture;
    GLuint _texCoordSlot;
//    GLuint _textureUniform;
    GLuint _yTextureUniform;
    GLuint _uTextureUniform;
    GLuint _vTextureUniform;
    
    // test code
    GLuint _fishTexture;    
}

@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) NSData *testYUVInputData;

@end

@implementation YUVDisplayGLViewController
@synthesize context = _context;
@synthesize testYUVInputData = _testYUVInputData;

- (void) awakeFromNib
{
    [super awakeFromNib];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)setupGL {
    
    [EAGLContext setCurrentContext:self.context];
    
    glGenBuffers(1, &_vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(Vertices), Vertices, GL_STATIC_DRAW);
    
    glGenBuffers(1, &_indexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBuffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(Indices), Indices, GL_STATIC_DRAW);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    
    [self setupGL];
    [self compileShaders];
 
    // test code load sample yuv frame
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *referenceFramePath = [mainBundle pathForResource:@"testOutput720x480_yuv420_1" ofType:@"yuv"];
    self.testYUVInputData = [NSData dataWithContentsOfFile:referenceFramePath];
    
    NSData *ydata = [NSData dataWithBytes:self.testYUVInputData.bytes length:720*480];
    NSData *udata = [NSData dataWithBytes:(void *)((uint8_t*)(self.testYUVInputData.bytes)+ydata.length) length:720*480/4];
    NSData *vdata = [NSData dataWithBytes:(void *)((uint8_t*)(self.testYUVInputData.bytes)+ydata.length+udata.length) length:720*480/4];
    
    
//    _fishTexture = [self setupTextureReference:@"item_powerup_fish.png"];
    _yTexture = [self setupTexture:ydata width:720 height:480];
    _uTexture = [self setupTexture:udata width:360 height:240];
    _vTexture = [self setupTexture:vdata width:360 height:240];
}

- (void)tearDownGL {
    
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_vertexBuffer);
    glDeleteBuffers(1, &_indexBuffer);
    
}

-(void)viewDidUnload
{
    [super viewDidUnload];
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
    self.context = nil;
    
    [self tearDownGL];
}
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - compile and load shaders

- (GLuint)compileShader:(NSString*)shaderString withType:(GLenum)shaderType
{
    GLuint shaderHandle = glCreateShader(shaderType);
    if (shaderHandle == 0 || shaderHandle == GL_INVALID_ENUM) {
        NSLog(@"Failed to create shader %d", shaderType);
        exit(1);
    }
    // 3
    const char * shaderStringUTF8 = [shaderString UTF8String];
    int shaderStringLength = [shaderString length];
    glShaderSource(shaderHandle, 1, &shaderStringUTF8, &shaderStringLength);
    
    // 4
    glCompileShader(shaderHandle);
    
    // 5
    GLint compileSuccess;
    glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
    if (compileSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetShaderInfoLog(shaderHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    return shaderHandle;
}

- (void) compileShaders
{
    GLuint vertexShader = [self compileShader:vertexShaderString
                                     withType:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShader:rgbFragmentShaderString
                                       withType:GL_FRAGMENT_SHADER];
    
    GLuint programHandle = glCreateProgram();
    glAttachShader(programHandle, vertexShader);
    glAttachShader(programHandle, fragmentShader);
    glLinkProgram(programHandle);
    
    GLint linkSuccess;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(programHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    glUseProgram(programHandle);
    
    _positionSlot = glGetAttribLocation(programHandle, "Position");
    _colorSlot = glGetAttribLocation(programHandle, "SourceColor");
    glEnableVertexAttribArray(_positionSlot);
    glEnableVertexAttribArray(_colorSlot);
    
    // set the shader slots
    _texCoordSlot = glGetAttribLocation(programHandle, "TexCoordIn");
    glEnableVertexAttribArray(_texCoordSlot);
//    _textureUniform = glGetUniformLocation(programHandle, "Texture");
    _yTextureUniform = glGetUniformLocation(programHandle, "s_texture_y");
    _uTextureUniform = glGetUniformLocation(programHandle, "s_texture_u");
    _vTextureUniform = glGetUniformLocation(programHandle, "s_texture_v");
}

#pragma mark - render code

- (void)render
{
    [EAGLContext setCurrentContext:self.context];
//    glClearColor(0, 104.0/255.0, 55.0/255.0, 1.0);
//    glClear(GL_COLOR_BUFFER_BIT);
    
    // 1
    CGFloat scaleFactor = [[UIScreen mainScreen] scale];
    glViewport(self.view.bounds.origin.x, self.view.bounds.origin.y,
               self.view.bounds.size.width*scaleFactor, self.view.bounds.size.height*scaleFactor);
    
    // 2
    glVertexAttribPointer(_positionSlot, 3, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), 0);
    glVertexAttribPointer(_colorSlot, 4, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (GLvoid*) (sizeof(float) * 3));
    
    // load the texture
    glVertexAttribPointer(_texCoordSlot, 2, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (GLvoid*) (sizeof(float) * 7));
    
    glActiveTexture(GL_TEXTURE0);
//    glBindTexture(GL_TEXTURE_2D, _fishTexture);
    glBindTexture(GL_TEXTURE_2D, _yTexture);
//    glUniform1i(_textureUniform, 0);
    glUniform1i(_yTextureUniform, 0);
    
    glActiveTexture(GL_TEXTURE0+1);
    glBindTexture(GL_TEXTURE_2D, _uTexture);
    glUniform1i(_uTextureUniform, 1);
    
    glActiveTexture(GL_TEXTURE0+2);
    glBindTexture(GL_TEXTURE_2D, _vTexture);
    glUniform1i(_vTextureUniform, 2);
    
    // 3
    glDrawElements(GL_TRIANGLES, sizeof(Indices)/sizeof(Indices[0]),
                   GL_UNSIGNED_BYTE, 0);
    
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
 
    
}


#pragma mark - texture setup

- (GLuint)setupTexture:(NSData *)textureData width:(uint) width height:(uint) height
{
    
    GLubyte *glTextureData = (GLubyte*)(textureData.bytes);
    GLuint texName;
    glGenTextures(1, &texName);
    glBindTexture(GL_TEXTURE_2D, texName);


    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, width, height, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, glTextureData);
//    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 100, 100, 0, GL_RGBA, GL_UNSIGNED_BYTE, glTextureData);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return texName;
}

- (GLuint)setupTextureReference:(NSString *)fileName
{
    // 1
    CGImageRef spriteImage = [UIImage imageNamed:fileName].CGImage;
    if (!spriteImage) {
        NSLog(@"Failed to load image %@", fileName);
        exit(1);
    }
    
    // 2
    size_t width = CGImageGetWidth(spriteImage);
    size_t height = CGImageGetHeight(spriteImage);
    
    GLubyte * spriteData = (GLubyte *) calloc(width*height*4, sizeof(GLubyte));
    
    CGContextRef spriteContext = CGBitmapContextCreate(spriteData, width, height, 8, width*4,
                                                       CGImageGetColorSpace(spriteImage), kCGImageAlphaPremultipliedLast);
    
    // 3
    CGContextDrawImage(spriteContext, CGRectMake(0, 0, width, height), spriteImage);
    
    CGContextRelease(spriteContext);
    
    // 4
    GLuint texName;
    glGenTextures(1, &texName);
    glBindTexture(GL_TEXTURE_2D, texName);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, spriteData);
    
    free(spriteData);        
    return texName;    
}

#pragma mark - GLKViewDelegate

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(_curRed, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    [self render];
}

#pragma mark - GLKViewControllerDelegate

- (void) update
{
    if (_increasing) {
        _curRed += 1.0 * self.timeSinceLastUpdate;
    } else {
        _curRed -= 1.0 * self.timeSinceLastUpdate;
    }
    if (_curRed >= 1.0) {
        _curRed = 1.0;
        _increasing = NO;
    }
    if (_curRed <= 0.0) {
        _curRed = 0.0;
        _increasing = YES;
    }
}

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    self.paused = !self.paused;
}
@end
