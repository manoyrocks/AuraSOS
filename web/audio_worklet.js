import './dsp_worklet.dart.js';

class AuraAudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    if (sampleRate !== 48000) {
      throw new Error('AuraSOS audio requires a 48000 Hz context');
    }
    this.dsp = globalThis.auraCreateDsp();
    this.disposed = false;
    this.port.onmessage = ({ data }) => {
      const [command, ...args] = data;
      switch (command) {
        case 'start': this.dsp.start(...args); break;
        case 'stop': this.dsp.stop(); break;
        case 'switchPreset': this.dsp.switchPreset(...args); break;
        case 'applyIso': this.dsp.applyIso(...args); break;
        case 'setProfileLimits': this.dsp.setProfileLimits(...args); break;
        case 'triggerNote': this.dsp.triggerNote(...args); break;
        case 'loadVoice': this.dsp.loadVoice(...args); break;
        case 'clearVoice': this.dsp.clearVoice(...args); break;
        case 'setVoiceWeave': this.dsp.setVoiceWeave(...args); break;
        case 'dispose':
          this.dsp.dispose();
          this.disposed = true;
          break;
        default: throw new Error(`Unknown AuraSOS audio command: ${command}`);
      }
    };
  }

  process(_inputs, outputs) {
    if (this.disposed) return false;
    const [left, right] = outputs[0];
    const samples = this.dsp.process(left.length);
    for (let i = 0; i < left.length; i++) {
      left[i] = samples[2 * i];
      right[i] = samples[2 * i + 1];
    }
    return true;
  }
}

registerProcessor('aura-dsp', AuraAudioProcessor);
