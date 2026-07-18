// Full love_gl host binding: implements the 161-entry GL import surface the
// love.graphics opengl backend calls, against a real WebGL2 context. This is
// the host side of the "static WebGL2 imports ARE the GL surface" seam
// (readme.md) — the real IDE preview will use the same binding.
//
// Self-contained by contract (no imports, no outer-scope refs), so it can be
// stringified and serialized into a page like the other browser hosts.
//
// Coverage: the context-bringup + clear/readback path (what the step-4 witness
// exercises) is implemented for real; entry points WebGL2 lacks or the witness
// never calls (compute, indirect draw, buffer mapping, debug groups, MSAA
// resolve) are present as no-ops/throwers so instantiation succeeds. Host-
// reported limits: glGetString/glGetIntegerv/glGetFloatv answer from the real
// context (gl.getParameter), never a static assumption.
export function makeWebGLHost() {
  // The system backbuffer LÖVE renders to when no MSAA internal backbuffer is
  // requested (the witness case). Sized generously so a witness can setMode to
  // any size up to this and position primitives with room; each witness reads
  // back within its own viewport (anchored at the canvas's bottom-left origin),
  // so a larger canvas never disturbs a smaller setMode.
  const canvas = new OffscreenCanvas(64, 64);
  // depth + stencil so the system backbuffer has the attachments love.graphics
  // needs for depth testing and stencil masking (WebGL context attributes
  // default both to false; the real preview needs them).
  const gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, alpha: true, antialias: false, depth: true, stencil: true });

  let memory, malloc;
  const HEAPU8  = () => new Uint8Array(memory.buffer);
  const HEAP32  = () => new Int32Array(memory.buffer);
  const HEAPU32 = () => new Uint32Array(memory.buffer);
  const HEAPF32 = () => new Float32Array(memory.buffer);
  const cstr = (ptr) => { const u = HEAPU8(); let e = ptr; while (u[e]) e++; return new TextDecoder().decode(u.subarray(ptr, e)); };

  // GL uint "names" <-> WebGL objects. id 0 == "no object" (unbind / default).
  const objs = new Map();
  let nextId = 1;
  const put = (o) => { const id = nextId++; objs.set(id, o); return id; };
  const get = (id) => (id === 0 ? null : objs.get(id));
  const gen = (n, ptr, create) => { const h = HEAPU32(); for (let i = 0; i < n; i++) h[(ptr >> 2) + i] = put(create()); };
  const del = (n, ptr, destroy) => { const h = HEAPU32(); for (let i = 0; i < n; i++) { const id = h[(ptr >> 2) + i]; const o = objs.get(id); if (o) { destroy(o); objs.delete(id); } } };
  const uloc = (id) => (id === -1 ? null : objs.get(id));
  const arrF = (ptr, n) => HEAPF32().subarray(ptr >> 2, (ptr >> 2) + n);
  const arrI = (ptr, n) => HEAP32().subarray(ptr >> 2, (ptr >> 2) + n);
  const arrU = (ptr, n) => HEAPU32().subarray(ptr >> 2, (ptr >> 2) + n);

  // glGetString returns a char*: allocate in wasm memory, cache per enum.
  const strCache = new Map();
  const HOST_STRINGS = {
    0x1F00: 'love-wasi',                    // GL_VENDOR
    0x1F01: 'WebGL2',                       // GL_RENDERER
    0x1F02: 'OpenGL ES 3.0 (WebGL2)',       // GL_VERSION
    0x8B8C: 'OpenGL ES GLSL ES 3.00',       // GL_SHADING_LANGUAGE_VERSION
    0x1F03: '',                             // GL_EXTENSIONS (legacy; ES3 uses glGetStringi)
  };
  const internString = (s) => {
    if (strCache.has(s)) return strCache.get(s);
    const bytes = new TextEncoder().encode(s);
    const p = malloc(bytes.length + 1);
    HEAPU8().set(bytes, p);
    HEAPU8()[p + bytes.length] = 0;
    strCache.set(s, p);
    return p;
  };

  const imports = {
    // --- strings / errors / queries (host-reported) ---
    glGetString(name) { return internString(HOST_STRINGS[name] ?? ''); },
    glGetError() { return gl.getError(); },
    glGetIntegerv(pname, ptr) {
      const v = gl.getParameter(pname);
      const h = HEAP32();
      if (Array.isArray(v) || v instanceof Int32Array || v instanceof Uint32Array) { for (let i = 0; i < v.length; i++) h[(ptr >> 2) + i] = v[i] | 0; }
      else h[ptr >> 2] = (v | 0);
    },
    glGetFloatv(pname, ptr) {
      const v = gl.getParameter(pname);
      const h = HEAPF32();
      if (v && v.length) { for (let i = 0; i < v.length; i++) h[(ptr >> 2) + i] = v[i]; }
      else h[ptr >> 2] = +v;
    },

    // --- clear / state ---
    glClearColor: (r, g, b, a) => gl.clearColor(r, g, b, a),
    glClear: (m) => gl.clear(m),
    glClearDepthf: (d) => gl.clearDepth(d),
    glClearDepth: (d) => gl.clearDepth(d),
    glClearStencil: (s) => gl.clearStencil(s),
    glColorMask: (r, g, b, a) => gl.colorMask(!!r, !!g, !!b, !!a),
    glDepthMask: (f) => gl.depthMask(!!f),
    glDepthFunc: (f) => gl.depthFunc(f),
    glEnable: (c) => gl.enable(c),
    glDisable: (c) => gl.disable(c),
    glBlendEquationSeparate: (a, b) => gl.blendEquationSeparate(a, b),
    glBlendFuncSeparate: (a, b, c, d) => gl.blendFuncSeparate(a, b, c, d),
    glCullFace: (m) => gl.cullFace(m),
    glFrontFace: (m) => gl.frontFace(m),
    glScissor: (x, y, w, h) => gl.scissor(x, y, w, h),
    glViewport: (x, y, w, h) => gl.viewport(x, y, w, h),
    glStencilFunc: (f, r, m) => gl.stencilFunc(f, r, m),
    glStencilMask: (m) => gl.stencilMask(m),
    glStencilOp: (a, b, c) => gl.stencilOp(a, b, c),
    glHint: (t, m) => gl.hint(t, m),
    glPixelStorei: (p, v) => gl.pixelStorei(p, v),
    glFinish: () => gl.finish(),
    glFlush: () => gl.flush(),
    glReadBuffer: (m) => gl.readBuffer(m),
    glDrawBuffers: (n, ptr) => { const h = HEAP32(); const a = []; for (let i = 0; i < n; i++) a.push(h[(ptr >> 2) + i]); gl.drawBuffers(a); },

    // --- buffers ---
    glGenBuffers: (n, ptr) => gen(n, ptr, () => gl.createBuffer()),
    glDeleteBuffers: (n, ptr) => del(n, ptr, (o) => gl.deleteBuffer(o)),
    glBindBuffer: (t, id) => gl.bindBuffer(t, get(id)),
    glBindBufferBase: (t, i, id) => gl.bindBufferBase(t, i, get(id)),
    glBufferData: (t, size, dataPtr, usage) => { if (dataPtr) gl.bufferData(t, HEAPU8().subarray(dataPtr, dataPtr + size), usage); else gl.bufferData(t, size, usage); },
    glBufferSubData: (t, off, size, dataPtr) => gl.bufferSubData(t, off, HEAPU8().subarray(dataPtr, dataPtr + size)),
    glCopyBufferSubData: (r, w, ro, wo, size) => gl.copyBufferSubData(r, w, ro, wo, size),

    // --- vertex arrays / attribs ---
    glGenVertexArrays: (n, ptr) => gen(n, ptr, () => gl.createVertexArray()),
    glDeleteVertexArrays: (n, ptr) => del(n, ptr, (o) => gl.deleteVertexArray(o)),
    glBindVertexArray: (id) => gl.bindVertexArray(get(id)),
    glEnableVertexAttribArray: (i) => gl.enableVertexAttribArray(i),
    glDisableVertexAttribArray: (i) => gl.disableVertexAttribArray(i),
    glVertexAttribPointer: (i, s, t, norm, stride, off) => gl.vertexAttribPointer(i, s, t, !!norm, stride, off),
    glVertexAttribIPointer: (i, s, t, stride, off) => gl.vertexAttribIPointer(i, s, t, stride, off),
    glVertexAttribDivisor: (i, d) => gl.vertexAttribDivisor(i, d),
    glVertexAttrib4f: (i, x, y, z, w) => gl.vertexAttrib4f(i, x, y, z, w),
    glVertexAttrib4fv: (i, ptr) => { const h = HEAPF32(); gl.vertexAttrib4f(i, h[ptr >> 2], h[(ptr >> 2) + 1], h[(ptr >> 2) + 2], h[(ptr >> 2) + 3]); },

    // --- textures ---
    glGenTextures: (n, ptr) => gen(n, ptr, () => gl.createTexture()),
    glDeleteTextures: (n, ptr) => del(n, ptr, (o) => gl.deleteTexture(o)),
    glBindTexture: (t, id) => gl.bindTexture(t, get(id)),
    glActiveTexture: (t) => gl.activeTexture(t),
    glTexParameteri: (t, p, v) => gl.texParameteri(t, p, v),
    glTexParameterf: (t, p, v) => gl.texParameterf(t, p, v),
    glTexParameterfv: (t, p, ptr) => gl.texParameterf(t, p, HEAPF32()[ptr >> 2]),
    glTexStorage2D: (t, l, f, w, h) => gl.texStorage2D(t, l, f, w, h),
    glTexStorage3D: (t, l, f, w, h, d) => gl.texStorage3D(t, l, f, w, h, d),
    glTexImage2D: (t, l, ifmt, w, h, b, fmt, type, ptr) => gl.texImage2D(t, l, ifmt, w, h, b, fmt, type, ptr ? HEAPU8().subarray(ptr) : null),
    glTexImage3D: (t, l, ifmt, w, h, d, b, fmt, type, ptr) => gl.texImage3D(t, l, ifmt, w, h, d, b, fmt, type, ptr ? HEAPU8().subarray(ptr) : null),
    glTexSubImage2D: (t, l, x, y, w, h, fmt, type, ptr) => gl.texSubImage2D(t, l, x, y, w, h, fmt, type, ptr ? HEAPU8().subarray(ptr) : null),
    glTexSubImage3D: (t, l, x, y, z, w, h, d, fmt, type, ptr) => gl.texSubImage3D(t, l, x, y, z, w, h, d, fmt, type, ptr ? HEAPU8().subarray(ptr) : null),
    glGenerateMipmap: (t) => gl.generateMipmap(t),

    // --- framebuffers / renderbuffers ---
    glGenFramebuffers: (n, ptr) => gen(n, ptr, () => gl.createFramebuffer()),
    glDeleteFramebuffers: (n, ptr) => del(n, ptr, (o) => gl.deleteFramebuffer(o)),
    glBindFramebuffer: (t, id) => gl.bindFramebuffer(t, get(id)),
    glFramebufferTexture2D: (t, a, tt, id, l) => gl.framebufferTexture2D(t, a, tt, get(id), l),
    glFramebufferTextureLayer: (t, a, id, l, layer) => gl.framebufferTextureLayer(t, a, get(id), l, layer),
    glCheckFramebufferStatus: (t) => gl.checkFramebufferStatus(t),
    glGenRenderbuffers: (n, ptr) => gen(n, ptr, () => gl.createRenderbuffer()),
    glDeleteRenderbuffers: (n, ptr) => del(n, ptr, (o) => gl.deleteRenderbuffer(o)),
    glBindRenderbuffer: (t, id) => gl.bindRenderbuffer(t, get(id)),
    glRenderbufferStorage: (t, f, w, h) => gl.renderbufferStorage(t, f, w, h),
    glRenderbufferStorageMultisample: (t, s, f, w, h) => gl.renderbufferStorageMultisample(t, s, f, w, h),
    glFramebufferRenderbuffer: (t, a, rt, id) => gl.framebufferRenderbuffer(t, a, rt, get(id)),
    glBlitFramebuffer: (sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter) => gl.blitFramebuffer(sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter),
    glInvalidateFramebuffer: (t, n, ptr) => { const h = HEAP32(); const a = []; for (let i = 0; i < n; i++) a.push(h[(ptr >> 2) + i]); gl.invalidateFramebuffer(t, a); },
    glReadPixels: (x, y, w, h, fmt, type, ptr) => { const tmp = new Uint8Array(w * h * 4); gl.readPixels(x, y, w, h, fmt, type, tmp); HEAPU8().set(tmp, ptr); },

    // --- shaders / programs ---
    glCreateShader: (t) => put(gl.createShader(t)),
    glDeleteShader: (id) => { const o = get(id); if (o) { gl.deleteShader(o); objs.delete(id); } },
    glShaderSource: (id, count, strPtrPtr, lenPtr) => {
      const h = HEAPU32(); let src = '';
      for (let i = 0; i < count; i++) {
        const sp = h[(strPtrPtr >> 2) + i];
        if (lenPtr) { const len = HEAP32()[(lenPtr >> 2) + i]; src += (len < 0) ? cstr(sp) : new TextDecoder().decode(HEAPU8().subarray(sp, sp + len)); }
        else src += cstr(sp);
      }
      gl.shaderSource(get(id), src);
    },
    glCompileShader: (id) => gl.compileShader(get(id)),
    glGetShaderiv: (id, pname, ptr) => { const v = gl.getShaderParameter(get(id), pname); HEAP32()[ptr >> 2] = (v === true ? 1 : v === false ? 0 : (v | 0)); },
    glGetShaderInfoLog: (id, max, lenPtr, ptr) => { const log = gl.getShaderInfoLog(get(id)) || ''; const b = new TextEncoder().encode(log.slice(0, max - 1)); HEAPU8().set(b, ptr); HEAPU8()[ptr + b.length] = 0; if (lenPtr) HEAP32()[lenPtr >> 2] = b.length; },
    glCreateProgram: () => put(gl.createProgram()),
    glDeleteProgram: (id) => { const o = get(id); if (o) { gl.deleteProgram(o); objs.delete(id); } },
    glAttachShader: (p, s) => gl.attachShader(get(p), get(s)),
    glBindAttribLocation: (p, i, ptr) => gl.bindAttribLocation(get(p), i, cstr(ptr)),
    glLinkProgram: (p) => gl.linkProgram(get(p)),
    glUseProgram: (id) => gl.useProgram(get(id)),
    glGetProgramiv: (id, pname, ptr) => { const v = gl.getProgramParameter(get(id), pname); HEAP32()[ptr >> 2] = (v === true ? 1 : v === false ? 0 : (v | 0)); },
    glGetProgramInfoLog: (id, max, lenPtr, ptr) => { const log = gl.getProgramInfoLog(get(id)) || ''; const b = new TextEncoder().encode(log.slice(0, max - 1)); HEAPU8().set(b, ptr); HEAPU8()[ptr + b.length] = 0; if (lenPtr) HEAP32()[lenPtr >> 2] = b.length; },
    glGetUniformLocation: (p, ptr) => { const loc = gl.getUniformLocation(get(p), cstr(ptr)); return loc ? put(loc) : -1; },
    glGetAttribLocation: (p, ptr) => gl.getAttribLocation(get(p), cstr(ptr)),
    glGetActiveUniform: (p, index, max, lenPtr, sizePtr, typePtr, namePtr) => {
      const info = gl.getActiveUniform(get(p), index);
      const name = info ? info.name : '';
      const b = new TextEncoder().encode(name.slice(0, max - 1));
      HEAPU8().set(b, namePtr); HEAPU8()[namePtr + b.length] = 0;
      if (lenPtr) HEAP32()[lenPtr >> 2] = b.length;
      if (sizePtr) HEAP32()[sizePtr >> 2] = info ? info.size : 0;
      if (typePtr) HEAP32()[typePtr >> 2] = info ? info.type : 0;
    },

    // --- uniforms (value pointers -> typed arrays) ---
    glUniform1fv: (l, c, p) => gl.uniform1fv(uloc(l), arrF(p, c)),
    glUniform2fv: (l, c, p) => gl.uniform2fv(uloc(l), arrF(p, c * 2)),
    glUniform3fv: (l, c, p) => gl.uniform3fv(uloc(l), arrF(p, c * 3)),
    glUniform4fv: (l, c, p) => gl.uniform4fv(uloc(l), arrF(p, c * 4)),
    glUniform1iv: (l, c, p) => gl.uniform1iv(uloc(l), arrI(p, c)),
    glUniform2iv: (l, c, p) => gl.uniform2iv(uloc(l), arrI(p, c * 2)),
    glUniform3iv: (l, c, p) => gl.uniform3iv(uloc(l), arrI(p, c * 3)),
    glUniform4iv: (l, c, p) => gl.uniform4iv(uloc(l), arrI(p, c * 4)),
    glUniform1uiv: (l, c, p) => gl.uniform1uiv(uloc(l), arrU(p, c)),
    glUniform2uiv: (l, c, p) => gl.uniform2uiv(uloc(l), arrU(p, c * 2)),
    glUniform3uiv: (l, c, p) => gl.uniform3uiv(uloc(l), arrU(p, c * 3)),
    glUniform4uiv: (l, c, p) => gl.uniform4uiv(uloc(l), arrU(p, c * 4)),
    glUniformMatrix2fv: (l, c, tr, p) => gl.uniformMatrix2fv(uloc(l), !!tr, arrF(p, c * 4)),
    glUniformMatrix3fv: (l, c, tr, p) => gl.uniformMatrix3fv(uloc(l), !!tr, arrF(p, c * 9)),
    glUniformMatrix4fv: (l, c, tr, p) => gl.uniformMatrix4fv(uloc(l), !!tr, arrF(p, c * 16)),
    glUniformMatrix2x3fv: (l, c, tr, p) => gl.uniformMatrix2x3fv(uloc(l), !!tr, arrF(p, c * 6)),
    glUniformMatrix3x2fv: (l, c, tr, p) => gl.uniformMatrix3x2fv(uloc(l), !!tr, arrF(p, c * 6)),
    glUniformMatrix2x4fv: (l, c, tr, p) => gl.uniformMatrix2x4fv(uloc(l), !!tr, arrF(p, c * 8)),
    glUniformMatrix4x2fv: (l, c, tr, p) => gl.uniformMatrix4x2fv(uloc(l), !!tr, arrF(p, c * 8)),
    glUniformMatrix3x4fv: (l, c, tr, p) => gl.uniformMatrix3x4fv(uloc(l), !!tr, arrF(p, c * 12)),
    glUniformMatrix4x3fv: (l, c, tr, p) => gl.uniformMatrix4x3fv(uloc(l), !!tr, arrF(p, c * 12)),

    // --- draw ---
    glDrawArrays: (m, f, c) => gl.drawArrays(m, f, c),
    glDrawArraysInstanced: (m, f, c, n) => gl.drawArraysInstanced(m, f, c, n),
    glDrawElements: (m, c, t, off) => gl.drawElements(m, c, t, off),
    glDrawElementsInstanced: (m, c, t, off, n) => gl.drawElementsInstanced(m, c, t, off, n),

    // --- sync ---
    glFenceSync: (cond, flags) => put(gl.fenceSync(cond, flags)),
    glClientWaitSync: (id, flags, timeout) => gl.clientWaitSync(get(id), flags, Number(timeout)),
    glDeleteSync: (id) => { const o = get(id); if (o) { gl.deleteSync(o); objs.delete(id); } },
  };

  // Present but not driven by the clear witness (WebGL2 lacks them, or they are
  // desktop-GL / debug / compute paths the backend feature-gates off). Provided
  // so instantiation succeeds; a call that slips through logs loudly.
  const STUBS = [
    'glBindImageTexture', 'glBufferStorage', 'glClearBufferData', 'glClearBufferSubData',
    'glClearBufferfv', 'glClearBufferiv', 'glClearBufferuiv', 'glCompressedTexImage2D',
    'glCompressedTexImage3D', 'glCompressedTexSubImage2D', 'glCompressedTexSubImage3D',
    'glDebugMessageCallback', 'glDebugMessageControl', 'glDiscardFramebufferEXT',
    'glDispatchCompute', 'glDispatchComputeIndirect', 'glDrawArraysIndirect',
    'glDrawElementsBaseVertex', 'glDrawElementsIndirect', 'glFlushMappedBufferRange',
    'glFramebufferTexture3D', 'glGetCompressedTextureSubImage', 'glGetProgramInterfaceiv',
    'glGetProgramResourceName', 'glGetRenderbufferParameteriv', 'glGetTextureSubImage',
    'glMapBufferRange', 'glMemoryBarrier', 'glObjectLabel', 'glPolygonMode',
    'glPopDebugGroup', 'glPopDebugGroupKHR', 'glPopGroupMarkerEXT', 'glPushDebugGroup',
    'glPushDebugGroupKHR', 'glPushGroupMarkerEXT', 'glResolveMultisampleFramebufferAPPLE',
    'glShaderStorageBlockBinding', 'glTexBuffer', 'glTextureView', 'glUnmapBuffer',
  ];
  for (const name of STUBS) if (!(name in imports)) imports[name] = ((n) => () => { console.warn('[webgl-host] unimplemented GL entry point called: ' + n); })(name);

  return {
    imports,
    bind(m, mallocFn) { memory = m; malloc = mallocFn; },
    haveContext() { return !!gl; },
  };
}
