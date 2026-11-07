import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = process.argv[2] ?? 'build/web';
let Processor;
const context = vm.createContext({
  console,
  sampleRate: 48000,
  AudioWorkletProcessor: class {
    constructor() { this.port = {}; }
  },
  registerProcessor(name, processor) {
    assert.equal(name, 'aura-dsp');
    Processor = processor;
  },
});
// No window, document, timers or Flutter: these do not exist on the audio thread.
vm.runInContext(fs.readFileSync(path.join(root, 'dsp_worklet.dart.js'), 'utf8'), context);
vm.runInContext(
  fs.readFileSync(path.join(root, 'audio_worklet.js'), 'utf8')
    .replace("import './dsp_worklet.dart.js';", ''),
  context,
);

function engine() {
  const processor = new Processor();
  return {
    processor,
    send(command, ...args) {
      processor.port.onmessage({ data: [command, ...args] });
    },
  };
}

const frames = 128;
const left = new Float32Array(frames);
const right = new Float32Array(frames);
const outputs = [[left, right]];

function render(e, seconds, beforeBlock = () => {}) {
  let peak = 0;
  const previous = e.previous ??= [0, 0];
  let tailPeak = 0;
  for (let block = 0; block < Math.ceil(seconds * 48000 / frames); block++) {
    beforeBlock(block);
    assert.equal(e.processor.process([], outputs), true);
    for (let i = 0; i < frames; i++) {
      for (const [channel, samples] of outputs[0].entries()) {
        const sample = samples[i];
        assert.ok(Number.isFinite(sample));
        assert.ok(Math.abs(sample) <= 0.70794578);
        assert.ok(Math.abs(sample - previous[channel]) < 0.005);
        previous[channel] = sample;
        peak = Math.max(peak, Math.abs(sample));
        if (block >= Math.ceil((seconds - 0.25) * 48000 / frames)) {
          tailPeak = Math.max(tailPeak, Math.abs(sample));
        }
      }
    }
  }
  return { peak, tailPeak };
}

for (let preset = 0; preset < 4; preset++) {
  const e = engine();
  e.send('setProfileLimits', 1000, 0.6, false);
  e.send('start', preset);
  e.send('applyIso', 72, 900, 0.5, 0.4, 0.3, 0.2);
  const playing = render(e, 6, (block) => {
    if (block % 47 === 0) e.send('triggerNote', block % 10, 0.6);
  });
  assert.ok(playing.peak > 0.001, `preset ${preset} must produce audio`);
  e.send('switchPreset', (preset + 1) % 4);
  render(e, 4.5);
  e.send('stop');
  assert.ok(render(e, 4.5).tailPeak < 1e-6, 'stop must fade to silence');
  e.send('dispose');
  assert.equal(e.processor.process([], outputs), false);
}

const e = engine();
e.send('loadVoice', 0, new Float32Array(48000).fill(0.1));
e.send('setVoiceWeave', true, 0.12, 10);
e.send('start', 1);
render(e, 22);
e.send('clearVoice', 0);
e.send('setVoiceWeave', false, 0.12, 45);
e.send('stop');
assert.ok(render(e, 4.5).tailPeak < 1e-6);
assert.throws(() => e.send('invalid'), /Unknown AuraSOS audio command/);
context.sampleRate = 44100;
assert.throws(() => new Processor(), /48000 Hz/);
console.log('AudioWorklet: all presets, tap spam, fades, limits and voice commands passed');
