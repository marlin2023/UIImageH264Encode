# UIImageH264Encode
UIImage convert to CVPixelBufferRef ,then be encoded by VideoToolBox api

- UIImageEncode01
	
	UIImage--> RGBA --> kCVPixelFormatType_420YpCbCr8Planar (YUV420p) --> CVPixelBufferRef --> CMSampleBufferRef --> Encode


- UIImageEncode02
	UIImage--> RGBA --> kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange 
	
		`size_t srcPlaneSize = frame_width * frame_height / 4;
		uint8_t *uDataAddr = _outbuffer_yuv + frame_width * frame_height;
		uint8_t *vDataAddr = uDataAddr + frame_width * frame_height / 4 ;

		for(size_t i = 0; i< srcPlaneSize; i++){
			_outbuffer_uv[2*i  ]=uDataAddr[i];
			_outbuffer_uv[2*i+1]=vDataAddr[i];
		}
		`
	--> CVPixelBufferRef --> CMSampleBufferRef --> Encode
	
	
	--> 这里说明下，使用 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange 作为CVPixelBufferRef 的format的话，uv存储要交错存储，对应ffmpeg中avframe理解的话就是二维的，不像Encode01中是三维的类似yuv420p存储。
	
参考
	- https://github.com/manishganvir/iOS-h264Hw-Toolbox
	- libyuv
	
	
