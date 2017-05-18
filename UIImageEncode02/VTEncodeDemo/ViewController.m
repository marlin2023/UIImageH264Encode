//
//  ViewController.m
//  VTEncodeDemo
//
//  Created by DevKS on 7/28/16.
//  Copyright © 2016 Shawn. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>

#import <VideoToolbox/VideoToolbox.h>

#include "libyuv.h"
//#include "rotate.h"

// 需实现 AVCaptureVideoDataOutputSampleBufferDelegate 用于获取摄像头数据
@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
{
    VTCompressionSessionRef _encodeSesion;
    dispatch_queue_t _encodeQueue;
    long    _frameCount;
    FILE    *_h264File;
    int     _spsppsFound;
    
    FILE    *_rgbFile;
    FILE    *_yuvFile;
    
    uint8_t* _outbuffer;
    uint8_t* _outbuffer_tmp;
    
    uint8_t* _outbuffer_yuv;
    uint8_t* _outbuffer_uv;
    
}

@property (nonatomic, strong)NSString *documentDictionary;

@property (nonatomic, strong)AVCaptureSession           *videoCaptureSession;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _encodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [self initVideoCaptrue];
    
    // 初始化_outbuffer
    int numBytes = 640 *480 *3 /2;
    _outbuffer = (uint8_t*)malloc(numBytes*sizeof(uint8_t));
    
    numBytes = 640 *480 * 4;
    _outbuffer_tmp = (uint8_t*)malloc(numBytes*sizeof(uint8_t));
    
    numBytes = 640 *480 * 3 / 2;
    _outbuffer_yuv = (uint8_t*)malloc(numBytes*sizeof(uint8_t));
    
    numBytes = 640 *480 / 2;
    _outbuffer_uv = (uint8_t*)malloc(numBytes*sizeof(uint8_t));
    
    // document directory 目录
    self.documentDictionary = [(NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES)) objectAtIndex:0];
    
    
}


- (IBAction)startButton:(UIButton *)sender
{
    // 文件保存在document文件夹下，可以直接通过iTunes将文件导出到电脑，在plist文件中添加Application supports iTunes file sharing = YES
    _h264File = fopen([[NSString stringWithFormat:@"%@/vt_encode.h264", self.documentDictionary] UTF8String], "wb");
    
    _yuvFile = fopen([[NSString stringWithFormat:@"%@/vt.yuv", self.documentDictionary] UTF8String], "wb");
    _rgbFile = fopen([[NSString stringWithFormat:@"%@/vt.rgb", self.documentDictionary] UTF8String], "wb");
    
    [self startEncodeSession:480 height:640 framerate:25 bitrate:640*1000];
    [self.videoCaptureSession startRunning];// 开始录像
    
}


- (IBAction)stopButton:(UIButton *)sender
{
    [self.videoCaptureSession stopRunning];
    
    [self stopEncodeSession];
    
    fclose(_h264File);
    fclose(_yuvFile);
    fclose(_rgbFile);
}

#pragma mark - camera
#pragma mark - video capture output delegate

+ (unsigned char *)pixelBRGABytesFromImageRef:(CGImageRef)imageRef {
    
    NSUInteger iWidth = CGImageGetWidth(imageRef);
    NSUInteger iHeight = CGImageGetHeight(imageRef);
    NSUInteger iBytesPerPixel = 4;
    NSUInteger iBytesPerRow = iBytesPerPixel * iWidth;
    NSUInteger iBitsPerComponent = 8;
    unsigned char *imageBytes = malloc(iWidth * iHeight * iBytesPerPixel);
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(imageBytes,
                                                 iWidth,
                                                 iHeight,
                                                 iBitsPerComponent,
                                                 iBytesPerRow,
                                                 colorspace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGRect rect = CGRectMake(0 , 0 , iWidth , iHeight);
    CGContextDrawImage(context , rect ,imageRef);
    CGColorSpaceRelease(colorspace);
    CGContextRelease(context);
    CGImageRelease(imageRef);
    
    return imageBytes;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    //[self encodeFrame:sampleBuffer];
    // TODO 这里读一个jpg ，然后处理 转换成 yuv pix format buffer data
//    UIImage *image = [UIImage imageNamed:@"480.jpg"];
    UIImage *image = [UIImage imageNamed:@"480_katong"];
    
    
    CGImageRef newCgImage = [image CGImage];
    CGDataProviderRef dataProvider = CGImageGetDataProvider(newCgImage);
    CFDataRef bitmapData = CGDataProviderCopyData(dataProvider);    // TODO how to free memory here .   CFRelease(bitmapData);      // ARC does not manage Core Foundation objects for you.
    // bitmapData 中上面UIImage 的原始像素数据
    
    _outbuffer = (uint8_t *)CFDataGetBytePtr(bitmapData);
    

    fwrite(_outbuffer, 1, 480*640*4, _rgbFile);
    
//    int width = 480;
//    int height = 640;
//    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
//    CGContextRef context = CGBitmapContextCreate(_outbuffer_tmp, width, height, 8, 480*4,
//                                                 colorSpaceRef,
//                                                 kCGImageAlphaPremultipliedLast);
//    CGContextSetBlendMode(context, kCGBlendModeCopy);
//    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), newCgImage);
//    CGContextRelease(context);
//    
//    CGColorSpaceRelease(colorSpaceRef);

    
    // convert color space 颜色空间转换
    int frame_width = 480;
    int frame_height = 640;
    ConvertToI420((uint8_t *)_outbuffer , 640 * 480,
                  _outbuffer_yuv, frame_width,
                  _outbuffer_yuv + frame_width * frame_height , frame_width /2 ,
                  _outbuffer_yuv + frame_width * frame_height *5 /4, frame_width /2 ,
                  0, 0,
                  480 ,640 ,//src_width, src_height,
                  480 ,640,
                  0, FOURCC_ABGR);  // FOURCC_RGBA  // FOURCC_ARGB  // FOURCC_BGRA
    
    fwrite(_outbuffer_yuv, 1, 480*640*3/2, _yuvFile);

    //
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             //@(avframe->linesize[0]), kCVPixelBufferBytesPerRowAlignmentKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferOpenGLESCompatibilityKey,
                             [NSDictionary dictionary], kCVPixelBufferIOSurfacePropertiesKey,
                             nil];
    
    // goujian start
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                          480, 640,
                                          //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,      // kCVPixelFormatType_420YpCbCr8Planar
                                          kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ,
                                          (__bridge CFDictionaryRef)(options),
                                          &pixelBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    
    //
    // interleave Cb and Cr plane
    
    size_t srcPlaneSize = frame_width * frame_height / 4;
    uint8_t *uDataAddr = _outbuffer_yuv + frame_width * frame_height;
    uint8_t *vDataAddr = uDataAddr + frame_width * frame_height / 4 ;
    
    for(size_t i = 0; i< srcPlaneSize; i++){
        _outbuffer_uv[2*i  ]=uDataAddr[i];
        _outbuffer_uv[2*i+1]=vDataAddr[i];
    }
    
    
    uint8_t *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    memcpy(yDestPlane, _outbuffer_yuv, frame_width * frame_height);
    
    uint8_t *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    memcpy(uvDestPlane, _outbuffer_uv, frame_width * frame_height/2);
    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    // TODO encode
    // CVPixelBufferRef pixelBuffer = [CVImageUtils pixelBufferFromCGImage:image];
    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleTimingInfo timimgInfo = kCMTimingInfoInvalid;
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(
                                                 NULL, pixelBuffer, &videoInfo);
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       pixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       videoInfo,
                                       &timimgInfo,
                                       &newSampleBuffer);

    [self encodeFrame:newSampleBuffer];
    
    CVPixelBufferRelease(pixelBuffer);
    CFRelease(bitmapData);
    
    // goujian end

    
    
    
    
}

- (void)initVideoCaptrue
{
    self.videoCaptureSession = [[AVCaptureSession alloc] init];
    
    // 设置录像分辨率
    [self.videoCaptureSession setSessionPreset:AVCaptureSessionPreset640x480];
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        NSLog(@"No Video device found");
        return;
    }
    
    AVCaptureDeviceInput *inputDevice = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
    
    if ([self.videoCaptureSession canAddInput:inputDevice]) {
        NSLog(@"add video input to video session: %@", inputDevice);
        [self.videoCaptureSession addInput:inputDevice];
    }
    
    AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    /* ONLY support pixel format : 420v, 420f, BGRA */
    dataOutput.videoSettings = [NSDictionary dictionaryWithObject:
                                          [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    if ([self.videoCaptureSession canAddOutput:dataOutput]) {
        NSLog(@"add video output to video session: %@", dataOutput);
        [self.videoCaptureSession addOutput:dataOutput];
    }
    
    // 设置采集图像的方向,如果不设置，采集回来的图形会是旋转90度的
    AVCaptureConnection *connection = [dataOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    [self.videoCaptureSession commitConfiguration];
    
    // 添加预览
    CGRect frame = self.view.frame;
    frame.size.height -= 50;
    AVCaptureVideoPreviewLayer *previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.videoCaptureSession];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [previewLayer setFrame:frame];
    [self.view.layer addSublayer:previewLayer];
    
    // 摄像头采集queue
    dispatch_queue_t queue = dispatch_queue_create("VideoCaptureQueue", DISPATCH_QUEUE_SERIAL);
    [dataOutput setSampleBufferDelegate:self queue:queue]; // 摄像头数据输出delegate
}


#pragma mark - videotoolbox methods
- (int)startEncodeSession:(int)width height:(int)height framerate:(int)fps bitrate:(int)bt
{
    OSStatus status;
    _frameCount = 0;

    VTCompressionOutputCallback cb = encodeOutputCallback;
    status = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, cb, (__bridge void *)(self), &_encodeSesion);
    
    if (status != noErr) {
        NSLog(@"VTCompressionSessionCreate failed. ret=%d", (int)status);
        return -1;
    }
    
    // 设置实时编码输出，降低编码延迟
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    NSLog(@"set realtime  return: %d", (int)status);

    // h264 profile, 直播一般使用baseline，可减少由于b帧带来的延时
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    NSLog(@"set profile   return: %d", (int)status);

    // 设置编码码率(比特率)，如果不设置，默认将会以很低的码率编码，导致编码出来的视频很模糊
    status  = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bt)); // bps
    status += VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)@[@(bt*2/8), @1]); // Bps
    NSLog(@"set bitrate   return: %d", (int)status);
    
    // 设置关键帧间隔，即gop size
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(fps*2));
    
    // 设置帧率，只用于初始化session，不是实际FPS
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(fps));
    NSLog(@"set framerate return: %d", (int)status);
    
    // 开始编码
    status = VTCompressionSessionPrepareToEncodeFrames(_encodeSesion);
    NSLog(@"start encode  return: %d", (int)status);
    
    return 0;
}


// 编码一帧图像，使用queue，防止阻塞系统摄像头采集线程
- (void) encodeFrame:(CMSampleBufferRef )sampleBuffer
{
    dispatch_sync(_encodeQueue, ^{
        CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // pts,必须设置，否则会导致编码出来的数据非常大，原因未知
        CMTime pts = CMTimeMake(_frameCount, 1000);
        CMTime duration = kCMTimeInvalid;
        
        VTEncodeInfoFlags flags;
        
        // 送入编码器编码
        OSStatus statusCode = VTCompressionSessionEncodeFrame(_encodeSesion,
                                                              imageBuffer,
                                                              pts, duration,
                                                              NULL, NULL, &flags);
        
        if (statusCode != noErr) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
            
            [self stopEncodeSession];
            return;
        }
    });
}

- (void) stopEncodeSession
{
    VTCompressionSessionCompleteFrames(_encodeSesion, kCMTimeInvalid);
    
    VTCompressionSessionInvalidate(_encodeSesion);
    
    CFRelease(_encodeSesion);
    _encodeSesion = NULL;
}

// 编码回调，每当系统编码完一帧之后，会异步掉用该方法，此为c语言方法
void encodeOutputCallback(void *userData, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                       CMSampleBufferRef sampleBuffer )
{
    if (status != noErr) {
        NSLog(@"didCompressH264 error: with status %d, infoFlags %d", (int)status, (int)infoFlags);
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    ViewController* vc = (__bridge ViewController*)userData;
    
    // 判断当前帧是否为关键帧
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    // 获取sps & pps数据. sps pps只需获取一次，保存在h264文件开头即可
    if (keyframe && !vc->_spsppsFound)
    {
        size_t spsSize, spsCount;
        size_t ppsSize, ppsCount;
        
        const uint8_t *spsData, *ppsData;
        
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        OSStatus err0 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 0, &spsData, &spsSize, &spsCount, 0 );
        OSStatus err1 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 1, &ppsData, &ppsSize, &ppsCount, 0 );

        if (err0==noErr && err1==noErr)
        {
            vc->_spsppsFound = 1;
            [vc writeH264Data:(void *)spsData length:spsSize addStartCode:YES];
            [vc writeH264Data:(void *)ppsData length:ppsSize addStartCode:YES];
            
            NSLog(@"got sps/pps data. Length: sps=%zu, pps=%zu", spsSize, ppsSize);
        }
    }
    
    size_t lengthAtOffset, totalLength;
    char *data;
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    OSStatus error = CMBlockBufferGetDataPointer(dataBuffer, 0, &lengthAtOffset, &totalLength, &data);
    
    if (error == noErr) {
        size_t offset = 0;
        const int lengthInfoSize = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (offset < totalLength - lengthInfoSize) {
            uint32_t naluLength = 0;
            memcpy(&naluLength, data + offset, lengthInfoSize); // 获取nalu的长度，
            
            // 大端模式转化为系统端模式
            naluLength = CFSwapInt32BigToHost(naluLength);
            NSLog(@"got nalu data, length=%d, totalLength=%zu", naluLength, totalLength);
            
            // 保存nalu数据到文件
            [vc writeH264Data:data+offset+lengthInfoSize length:naluLength addStartCode:YES];
            
            // 读取下一个nalu，一次回调可能包含多个nalu
            offset += lengthInfoSize + naluLength;
        }
    }
}

// 保存h264数据到文件
- (void) writeH264Data:(void*)data length:(size_t)length addStartCode:(BOOL)b
{
    // 添加4字节的 h264 协议 start code
    const Byte bytes[] = "\x00\x00\x00\x01";
    
    if (_h264File) {
        if(b)
            fwrite(bytes, 1, 4, _h264File);
        
        fwrite(data, 1, length, _h264File);
    } else {
        NSLog(@"_h264File null error, check if it open successed");
    }
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
