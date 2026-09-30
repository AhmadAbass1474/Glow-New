// قائمة إعدادات شخصيات الأصوات المعتمدة في ElevenLabs
const VOICE_SETTINGS = {
  port: {
    voiceId: "YOUR_PORT_VOICE_ID", // ضع ID الخاص بشخصية port هنا
    settings: {
      speed: 1.14,
      stability: 0.50,
      similarity_boost: 0.84,
      style: 0.73,
      use_speaker_boost: true
    }
  },
  leo: {
    voiceId: "YOUR_LEO_VOICE_ID", // ضع ID الخاص بشخصية leo هنا
    settings: {
      speed: 0.94,
      stability: 0.89,
      similarity_boost: 0.91,
      style: 0.73,
      use_speaker_boost: true
    }
  },
  qort: { // Elmoe
    voiceId: "YOUR_QORT_VOICE_ID", // ضع ID الخاص بشخصية qort هنا
    settings: {
      speed: 1.04,
      stability: 0.60,
      similarity_boost: 0.96,
      style: 0.63,
      use_speaker_boost: true
    }
  },
  sort: { // Mimi
    voiceId: "CBDgRB8OyxYGowoi5iXR", // تم تحديث الـ Voice ID المطلوب
    settings: {
      speed: 0.87,
      stability: 0.63,
      similarity_boost: 1.00,
      style: 0.94,
      use_speaker_boost: true
    }
  },
  marwat: {
    voiceId: "YOUR_MARWAT_VOICE_ID", // ضع ID الخاص بشخصية marwat هنا
    settings: {
      speed: 1.00,
      stability: 0.76,
      similarity_boost: 0.85,
      style: 0.68,
      use_speaker_boost: true
    }
  }
};

/**
 * دالة توليد الصوت باستعمال ElevenLabs API
 * @param {string} characterKey - اسم الشخصية (port, leo, qort, sort, marwat)
 * @param {string} text - النص المراد تحويله إلى صوت
 * @param {string} apiKey - مفتاح ElevenLabs API
 */
async function generateSpeech(characterKey, text, apiKey) {
  const character = VOICE_SETTINGS[characterKey];

  if (!character) {
    throw new Error(`الشخصية المحدد "${characterKey}" غير موجودة في الإعدادات.`);
  }

  const url = `https://api.elevenlabs.io/v1/text-to-speech/${character.voiceId}`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Accept": "audio/mpeg",
      "Content-Type": "application/json",
      "xi-api-key": apiKey
    },
    body: JSON.stringify({
      text: text,
      model_id: "eleven_multilingual_v2", // النموذج المعتمد v2
      voice_settings: {
        stability: character.settings.stability,
        similarity_boost: character.settings.similarity_boost,
        style: character.settings.style,
        use_speaker_boost: character.settings.use_speaker_boost,
        speed: character.settings.speed
      }
    })
  });

  if (!response.ok) {
    const errorData = await response.json();
    throw new Error(`خطأ في ElevenLabs API: ${JSON.stringify(errorData)}`);
  }

  const audioBuffer = await response.arrayBuffer();
  return audioBuffer;
}