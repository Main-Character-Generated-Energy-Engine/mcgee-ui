import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const source = await readFile(new URL("../web/capture_image.js", import.meta.url), "utf8");

test("browser capture uses native codecs and bounds the longest edge", async () => {
  const canvases = [];
  const bitmaps = [];
  const context = vm.createContext({
    Blob,
    Uint8Array,
    createImageBitmap: async () => {
      const bitmap = { width: 1440, height: 960, closed: false,
        close() { this.closed = true; } };
      bitmaps.push(bitmap);
      return bitmap;
    },
    document: {
      createElement(name) {
        assert.equal(name, "canvas");
        const canvas = {
          width: 0, height: 0, quality: null, drawn: false,
          getContext(kind) {
            assert.equal(kind, "2d");
            return { drawImage: (bitmap, x, y, width, height) => {
              assert.equal(bitmap, bitmaps.at(-1));
              assert.deepEqual([x, y, width, height], [0, 0, 512, 341]);
              canvas.drawn = true;
            } };
          },
          toBlob(callback, type, quality) {
            assert.equal(type, "image/jpeg");
            canvas.quality = quality;
            callback(new Blob([Uint8Array.of(1, 2, 3)], { type }));
          },
        };
        canvases.push(canvas);
        return canvas;
      },
    },
  });
  vm.runInContext(source, context);

  const output = await context.McGeeOptimizeCapture(Uint8Array.of(9), 512, 0.65);
  assert.deepEqual(Array.from(output), [1, 2, 3]);
  assert.deepEqual([canvases[0].width, canvases[0].height], [512, 341]);
  assert.equal(canvases[0].quality, 0.65);
  assert.equal(canvases[0].drawn, true);
  assert.equal(bitmaps[0].closed, true);
});
