// Decode, resize, and re-encode camera JPEGs with browser image codecs. This
// removes metadata and avoids the Dart image package's main-thread JPEG loops.
globalThis.McGeeOptimizeCapture = async (bytes, longestEdge, quality) => {
  const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/jpeg" }));
  try {
    const scale = Math.min(1, longestEdge / Math.max(bitmap.width, bitmap.height));
    const width = Math.max(1, Math.round(bitmap.width * scale));
    const height = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Camera image resizing is unavailable.");
    context.drawImage(bitmap, 0, 0, width, height);
    const output = await new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (blob) resolve(blob);
        else reject(new Error("Camera image encoding failed."));
      }, "image/jpeg", quality);
    });
    return new Uint8Array(await output.arrayBuffer());
  } finally {
    bitmap.close();
  }
};
