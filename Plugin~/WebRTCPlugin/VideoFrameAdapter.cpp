#include "pch.h"

#include <api/video/video_frame.h>

#include "VideoFrameAdapter.h"

namespace unity
{
namespace webrtc
{
    template<typename T>
    bool Contains(rtc::ArrayView<T> arr, T value)
    {
        for (auto e : arr)
        {
            if (e == value)
                return true;
        }
        return false;
    }

    ::webrtc::VideoFrame VideoFrameAdapter::CreateVideoFrame(rtc::scoped_refptr<VideoFrame> frame)
    {
        rtc::scoped_refptr<VideoFrameAdapter> adapter(new rtc::RefCountedObject<VideoFrameAdapter>(std::move(frame)));

        return ::webrtc::VideoFrame::Builder().set_video_frame_buffer(adapter).build();
    }

    VideoFrameAdapter::ScaledBuffer::ScaledBuffer(rtc::scoped_refptr<VideoFrameAdapter> parent, int width, int height)
        : parent_(parent)
        , width_(width)
        , height_(height)
    {
    }

    VideoFrameAdapter::ScaledBuffer::~ScaledBuffer() { }

    VideoFrameBuffer::Type VideoFrameAdapter::ScaledBuffer::type() const { return parent_->type(); }

    rtc::scoped_refptr<webrtc::I420BufferInterface> VideoFrameAdapter::ScaledBuffer::ToI420()
    {
        auto buffer = parent_->GetOrCreateFrameBufferForSize(Size(width_, height_));
        if(!buffer)
        {
            RTC_LOG(LS_ERROR) << "VideoFrameAdapter::ScaledBuffer::ToI420 buffer is null.";
            return nullptr;
        }
        return buffer->ToI420();
    }

    const I420BufferInterface* VideoFrameAdapter::ScaledBuffer::GetI420() const
    {
        auto buffer = parent_->GetOrCreateFrameBufferForSize(Size(width_, height_));
        if(!buffer)
        {
            RTC_LOG(LS_ERROR) << "VideoFrameAdapter::ScaledBuffer::GetI420 buffer is null.";
            return nullptr;
        }
        return buffer->GetI420();
    }

    rtc::scoped_refptr<VideoFrameBuffer>
    VideoFrameAdapter::ScaledBuffer::GetMappedFrameBuffer(rtc::ArrayView<VideoFrameBuffer::Type> types)
    {
        auto buffer = parent_->GetOrCreateFrameBufferForSize(Size(width_, height_));
        if(!buffer)
        {
            return nullptr;
        }
        return Contains(types, buffer->type()) ? buffer : nullptr;
    }

    rtc::scoped_refptr<VideoFrameBuffer> VideoFrameAdapter::ScaledBuffer::CropAndScale(
        int offset_x, int offset_y, int crop_width, int crop_height, int scaled_width, int scaled_height)
    {
        return rtc::make_ref_counted<ScaledBuffer>(
            rtc::scoped_refptr<VideoFrameAdapter>(parent_), scaled_width, scaled_height);
    }

    VideoFrameAdapter::VideoFrameAdapter(rtc::scoped_refptr<VideoFrame> frame)
        : frame_(std::move(frame))
        , size_(frame_->size())
    {
    }

    VideoFrameAdapter::~VideoFrameAdapter()
    {
        {
            std::unique_lock<std::mutex> lock1(scaleLock_);
            std::unique_lock<std::mutex> lock2(convertLock_);
        }
    }

    VideoFrameBuffer::Type VideoFrameAdapter::type() const
    {
#if UNITY_IOS || UNITY_OSX || UNITY_ANDROID
        // todo(kazuki): support for kNative type for mobile platform and macOS.
        // Need to pass ObjCFrameBuffer instead of VideoFrameAdapter on macOS/iOS.
        // Need to pass AndroidVideoBuffer instead of VideoFrameAdapter on Android.
        return VideoFrameBuffer::Type::kI420;
#else
        return VideoFrameBuffer::Type::kNative;
#endif
    }

    const I420BufferInterface* VideoFrameAdapter::GetI420() const
    {
        auto buffer = ConvertToVideoFrameBuffer(frame_);
        if(!buffer)
        {
            RTC_LOG(LS_ERROR) << "VideoFrameAdapter::GetI420 buffer is null.";
            return nullptr;
        }
        return buffer->GetI420();
    }

    rtc::scoped_refptr<I420BufferInterface> VideoFrameAdapter::ToI420()
    {
        auto buffer = ConvertToVideoFrameBuffer(frame_);
        if(!buffer)
        {
            RTC_LOG(LS_ERROR) << "VideoFrameAdapter::ToI420 buffer is null.";
            return nullptr;
        }
        return buffer->ToI420();
    }

    rtc::scoped_refptr<VideoFrameBuffer> VideoFrameAdapter::CropAndScale(
        int offset_x, int offset_y, int crop_width, int crop_height, int scaled_width, int scaled_height)
    {
        auto frame = rtc::scoped_refptr<VideoFrameAdapter>(this);
        auto buffer = rtc::make_ref_counted<ScaledBuffer>(frame, scaled_width, scaled_height);
        return buffer;
    }

    rtc::scoped_refptr<VideoFrameBuffer> VideoFrameAdapter::GetOrCreateFrameBufferForSize(const Size& size)
    {
        std::unique_lock<std::mutex> guard(scaleLock_);

        for (auto scaledI420buffer : scaledI40Buffers_)
        {
            Size bufferSize(scaledI420buffer->width(), scaledI420buffer->height());
            if (size == bufferSize)
            {
                return scaledI420buffer;
            }
        }
        auto buffer = VideoFrameBuffer::CropAndScale(0, 0, width(), height(), size.width(), size.height());
        scaledI40Buffers_.push_back(buffer);
        return buffer;
    }

    rtc::scoped_refptr<I420BufferInterface>
    VideoFrameAdapter::ConvertToVideoFrameBuffer(rtc::scoped_refptr<VideoFrame> video_frame) const
    {
        std::unique_lock<std::mutex> guard(convertLock_);
        if (i420Buffer_)
            return i420Buffer_;

        RTC_DCHECK(video_frame);
        RTC_DCHECK(video_frame->HasGpuMemoryBuffer());

        auto gmb = video_frame->GetGpuMemoryBuffer();
        i420Buffer_ = gmb->ToI420();
        return i420Buffer_;
    }

}
}
