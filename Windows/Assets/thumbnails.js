'use strict';
// Decode one video at a time, never play it, and release the decoder after capture.
// The host persists one small JPEG per imported video, including existing libraries.
window.thumbnailPreviews = (() => {
  const attempted = new Set(), pending = new Map(), retried = new Set();
  let running = false;
  function capture(filename) {
    return new Promise((resolve, reject) => {
      const video = document.createElement('video');
      video.muted = true; video.preload = 'auto'; video.crossOrigin = 'anonymous';
      const finish = (error, jpeg) => {
        clearTimeout(timeout);
        video.onloadedmetadata = video.onloadeddata = video.onseeked = video.onerror = null;
        video.pause(); video.removeAttribute('src'); video.load();
        error ? reject(error) : resolve(jpeg);
      };
      const timeout = setTimeout(() => finish(new Error('Preview timed out')), 15000);
      const draw = () => {
        if (!video.videoWidth || !video.videoHeight) return;
        try {
          const canvas = document.createElement('canvas');
          const scale = Math.min(480 / video.videoWidth, 270 / video.videoHeight, 1);
          canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
          canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
          canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
          const jpeg = canvas.toDataURL('image/jpeg', .8).split(',')[1];
          canvas.width = canvas.height = 0;
          finish(null, jpeg);
        } catch (error) { finish(error); }
      };
      let seekTo = 0;
      video.onloadedmetadata = () => {
        seekTo = Number.isFinite(video.duration) ? Math.min(1, video.duration / 10) : 0;
        if (seekTo > 0) video.currentTime = seekTo;
      };
      video.onseeked = draw;
      video.onloadeddata = () => { if (seekTo === 0) draw(); };
      video.onerror = () => finish(new Error('Video codec unavailable'));
      video.src = 'https://media.openwall.local/' + encodeURIComponent(filename);
    });
  }
  async function pump() {
    if (running) return;
    running = true;
    try {
      while (pending.size) {
        const [id, filename] = pending.entries().next().value;
        pending.delete(id); attempted.add(id);
        try {
          const jpeg = await capture(filename);
          window.chrome?.webview?.postMessage({command:'thumbnail', id, jpeg});
        } catch { /* Keep the video fallback; retry next time the app opens. */ }
      }
    } finally { running = false; }
  }
  return {
    retry(id) {
      if (retried.has(id)) return false;
      retried.add(id); attempted.delete(id);
      return true;
    },
    update(items) {
      const current = new Set(items.filter(w => w.filename && !w.thumbnail).map(w => w.id));
      for (const id of pending.keys()) if (!current.has(id)) pending.delete(id);
      for (const item of items)
        if (current.has(item.id) && !attempted.has(item.id)) pending.set(item.id, item.filename);
      void pump();
    }
  };
})();
