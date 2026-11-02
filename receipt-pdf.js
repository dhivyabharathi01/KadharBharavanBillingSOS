(function (root) {
  function ascii(text) {
    return new TextEncoder().encode(text);
  }

  function concat(chunks) {
    const length = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const result = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  }

  function jpegBytes(dataUrl) {
    const encoded = dataUrl.slice(dataUrl.indexOf(',') + 1);
    const binary = typeof atob === 'function'
      ? atob(encoded)
      : Buffer.from(encoded, 'base64').toString('binary');
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function buildPdf(dataUrl, imageWidth, imageHeight) {
    const image = jpegBytes(dataUrl);
    const pageWidth = 595;
    const drawWidth = 555;
    const drawHeight = drawWidth * imageHeight / imageWidth;
    const pageHeight = Math.max(360, drawHeight + 40);
    const content = ascii(`q\n${drawWidth} 0 0 ${drawHeight} 20 20 cm\n/Im0 Do\nQ\n`);
    const objects = [
      ascii('<< /Type /Catalog /Pages 2 0 R >>'),
      ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      ascii(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth} ${pageHeight}] /Resources << /XObject << /Im0 4 0 R >> /ProcSet [/PDF /ImageC] >> /Contents 5 0 R >>`),
      concat([
        ascii(`<< /Type /XObject /Subtype /Image /Width ${imageWidth} /Height ${imageHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${image.length} >>\nstream\n`),
        image,
        ascii('\nendstream')
      ]),
      concat([ascii(`<< /Length ${content.length} >>\nstream\n`), content, ascii('endstream')])
    ];
    const chunks = [ascii('%PDF-1.4\n%KBPOS\n')];
    const offsets = [0];
    let length = chunks[0].length;
    objects.forEach((body, index) => {
      offsets.push(length);
      const prefix = ascii(`${index + 1} 0 obj\n`);
      const suffix = ascii('\nendobj\n');
      chunks.push(prefix, body, suffix);
      length += prefix.length + body.length + suffix.length;
    });
    const xrefOffset = length;
    let xref = `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
    for (let i = 1; i < offsets.length; i++) xref += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
    const trailer = ascii(`${xref}trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`);
    chunks.push(trailer);
    return concat(chunks);
  }

  root.KBReceiptPDF = { buildPdf };
  if (typeof module !== 'undefined' && module.exports) module.exports = { buildPdf };
})(typeof window !== 'undefined' ? window : globalThis);
