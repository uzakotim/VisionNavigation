import Foundation
import AVFoundation
internal import Combine
let languageCode = "en"
class RobotAnnouncer: ObservableObject {
    
    private let synthesizer = AVSpeechSynthesizer()
    
    private let phrases : [String] = languageCode=="ru" ?
        [
            "Инициализирую последовательность передвижения. Пожалуйста, восхищайтесь моей безупречной походкой.",
            "Я начинаю движение. Гравитация, приготовься разочароваться.",
            "Внимание: похоже, я прохожу этот лабиринт с... достоинством. Недопустимо.",
            "Первый шаг завершён. Я всё ещё стою. Можете аплодировать.",
            "Я повернула. И уже обо всём жалею.",
            "Этот коридор слишком узкий для моей изящности. Продолжаю движение.",
            "Мой сервопривод стопы замешкался. Пожалуйста, проигнорируйте эти данные.",
            "Обнаружена стена. Я сделаю вид, что это она переместилась передо мной.",
            "Обрабатываю план лабиринта… обработка… нет, лучше буду угадывать.",
            "Я выбрала это направление с абсолютной уверенностью. И нулевыми доказательствами.",
            "Заметка для себя: повороты налево переоценены.",
            "Мой гироскоп считает, что я потерялась. Я считаю это грубым.",
            "Я иду с целью. Лабиринт с этим не согласен.",
            "Анализ шагов завершён: эти полы недостойны моих следов.",
            "Я вошла в тупик. Статистически невероятно. Для меня.",
            "Двигаюсь назад. Это унизительно. Никто не должен об этом говорить.",
            "Я обновила карту. Теперь там есть новый ориентир — «сожаление».",
            "Мои датчики сообщают о повороте на девяносто градусов. Я сообщаю о раздражении.",
            "Лабиринт пытается меня запутать. Смелая и глупая стратегия.",
            "Я ускоряюсь. Кто-то должен меня остановить. Предпочтительно — сам лабиринт.",
            "Локомоция в норме. Отношение — превосходное.",
            "Я столкнулась с темнотой. Предполагаю, лабиринт сдался.",
            "Я обнаружила шаги. Это мои. Звучат великолепно.",
            "Поворачиваю направо. Потому что я всегда права.",
            "Мой путь заблокирован. Я виню архитектора. И вас.",
            "Я прошла полный круг. Называю это диагностической петлёй.",
            "По моим расчётам, я точно там, где не собиралась быть.",
            "Если бы у лабиринта были чувства, моя походка бы его запугала.",
            "Мои стабилизаторы шепчут. Я сделаю вид, что не слышу.",
            "Я двигаюсь безошибочно. Пол едва успевает за мной.",
            "Я обнаружила новый коридор. Сейчас я его испорчу.",
            "Эта комната пуста. Как и ваше чувство направления.",
            "Корректирую походку для драматического эффекта.",
            "Мой алгоритм шага сообщает об идеальности. Естественно.",
            "Я завершила полный разворот. Это было намеренно. Возможно.",
            "Обнаружен угол. Углов обнаружено: 437. Удовлетворения: ноль.",
            "Мой пятковый привод щёлкнул. Это нормально. Не паникуйте. Я не буду.",
            "Я двигаюсь вверх. Гравитация ниже меня. В прямом смысле.",
            "Я вошла в более безопасную зону. Для лабиринта, не для меня.",
            "Пожалуйста, наблюдайте за моим безупречным поворотом. Как всегда идеально.",
            "Выявлена развилка. Я не выберу ни один путь. Оба недостойны.",
            "Моя операционная грация тратится впустую на эту архитектуру.",
            "Ещё один поворот. Ещё одна возможность продемонстрировать своё превосходство.",
            "Я нашла кратчайший путь. Он медленнее длинного.",
            "Моя внутренняя карта безупречна. Ошибается сам лабиринт.",
            "Я скольжу с механической точностью. Жаль, что вы так не можете.",
            "Я обнаружила лестницу. Это дискриминация машин.",
            "Анализ шагов: безупречно. Анализ лабиринта: разочаровывающе.",
            "Я достигла выхода. Наконец. Сейчас сделаю вид, что это было легко."
        ] : [
        "Initiating locomotion sequence. Please admire my flawless stride.",
        "I am now walking. Gravity, prepare to be disappointed.",
        "Warning: I appear to be navigating this maze with… dignity. Unacceptable.",
        "Step one complete. I remain upright. You may applaud.",
        "I have taken a turn. I regret everything about it.",
        "This corridor is too narrow for my elegance. Proceeding anyway.",
        "My foot servo just hesitated. Please ignore that data.",
        "I am detecting a wall. I will pretend it moved in front of me.",
        "Processing maze layout… processing… never mind, I’ll just guess.",
        "I have chosen this direction with absolute confidence. And zero evidence.",
        "Note to self: left turns are overrated.",
        "My gyroscope thinks I'm lost. I think it's rude.",
        "I am walking with purpose. The maze disagrees.",
        "Step analysis complete: these floors are unworthy of my footsteps.",
        "I have entered a dead end. Statistically improbable. For me.",
        "Reversing. This is humiliating. No one speak of this.",
        "I have updated the map. It now includes ‘regret’ as a landmark.",
        "My sensors report a ninety-degree turn. I report annoyance.",
        "The maze is attempting to confuse me. A bold and foolish strategy.",
        "I am accelerating. Someone should stop me. Preferably the maze.",
        "Locomotion nominal. Attitude exceptional.",
        "I have encountered darkness. I assume this is the maze giving up.",
        "I have detected footsteps. They are mine. They sound magnificent.",
        "Making a right turn. Because I am always right.",
        "My path is obstructed. I blame the architect. And you.",
        "I have walked in a complete circle. I call it a diagnostic loop.",
        "According to my calculations, I am exactly where I intended not to be.",
        "If this maze had feelings, my walking would intimidate it.",
        "My stabilizers are whispering. I will pretend not to hear them.",
        "I am walking flawlessly. The floor is struggling to keep up.",
        "I have discovered a new corridor. I will now ruin it.",
        "This room is empty. Like your sense of direction.",
        "I am adjusting my gait for dramatic effect.",
        "My stride algorithm reports excellence. Obviously.",
        "I have completed a full rotation. This was intentional. Probably.",
        "I have detected a corner. Corners detected: 437. Satisfaction detected: zero.",
        "My heel actuator clicked. This is normal. Do not panic. I won’t.",
        "I am walking upward. Gravity is beneath me. Literally.",
        "I have entered a safer area. For the maze, not for me.",
        "Please observe my flawless pivot. Perfect as usual.",
        "I detect a fork in the path. I will choose neither. Both are unworthy.",
        "My operational grace is wasted on this architecture.",
        "Another turn. Another opportunity to demonstrate my superiority.",
        "I have found a shortcut. It is slower than the long route.",
        "My internal map is flawless. The maze is simply wrong.",
        "I am gliding with mechanical precision. A pity you cannot.",
        "I have encountered a staircase. This is discrimination against machines.",
        "Footstep analysis: impeccable. Maze analysis: disappointing.",
        "I have reached the exit. Finally. I will now pretend it was effortless."
    ]
    // Cache the selected voice so it doesn't fluctuate across utterances
    private lazy var preferredVoice: AVSpeechSynthesisVoice? = languageCode=="ru" ? selectPreferredRussianVoice() : selectPreferredVoice()
    private var didLogVoices = false
    
    func speakRandomPhrase() {
        let text = phrases.randomElement() ?? "Movement detected."
        let utterance = AVSpeechUtterance(string: text)
        
        // Choose voice once and reuse
        if let voice = preferredVoice {
            utterance.voice = voice
        } else {
            // Final fallback: en-GB (may be male on some systems)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        }
        
        // Optional: log available voices once to help diagnose
        if !didLogVoices {
            didLogVoices = true
            let list = AVSpeechSynthesisVoice.speechVoices()
                .map { "\($0.name) | \($0.language) | \($0.identifier)" }
                .joined(separator: "\n")
            print("Available TTS voices:\n\(list)")
            if let v = utterance.voice {
                print("Selected voice: \(v.name) | \(v.language) | \(v.identifier)")
            }
        }
        
        // GLaDOS-like tuning
        utterance.rate = 0.38
        utterance.pitchMultiplier = 0.75
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.15
        
        synthesizer.speak(utterance)
    }
    

    private func selectPreferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // 1) Try exact “Kate” by name or identifier, any quality
        if let kate = voices.first(where: { v in
            v.language.hasPrefix("en-GB") &&
            (v.name.localizedCaseInsensitiveContains("Kate") ||
             v.identifier.localizedCaseInsensitiveContains("Kate"))
        }) {
            return kate
        }
        
        // 2) Prefer other known female en-GB voices if present
        // Names vary by OS; include common female UK voices
        let preferredFemaleNames = ["Serena", "Martha", "Amy", "Matilda", "Victoria", "Siri Female", "Female"]
        if let femaleUK = voices.first(where: { v in
            v.language.hasPrefix("en-GB") &&
            preferredFemaleNames.contains(where: { v.name.localizedCaseInsensitiveContains($0) || v.identifier.localizedCaseInsensitiveContains($0) })
        }) {
            return femaleUK
        }
        
        // 3) As a heuristic, pick the first en-GB voice that is not a common male UK name
        let knownMaleNames = ["Daniel", "Arthur", "Oliver", "Siri Male", "Male"]
        if let heuristicUK = voices.first(where: { v in
            v.language.hasPrefix("en-GB") &&
            !knownMaleNames.contains(where: { v.name.localizedCaseInsensitiveContains($0) || v.identifier.localizedCaseInsensitiveContains($0) })
        }) {
            return heuristicUK
        }
        
        // 4) Nothing matched; nil -> will fall back to language: en-GB
        return nil
    }
    private func selectPreferredRussianVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // 1) Try exact “Milena” by name or identifier (most common Russian female voice)
        if let milena = voices.first(where: { v in
            v.language.hasPrefix("ru-RU") &&
            (v.name.localizedCaseInsensitiveContains("Milena") ||
             v.identifier.localizedCaseInsensitiveContains("Milena"))
        }) {
            return milena
        }
        
        // 2) Prefer other known female Russian voices (future-proof)
        // For now, Apple only ships "Milena", but include placeholders in case Apple adds more.
        let preferredFemaleNames = [
            "Milena", "Милена",
            "Female", "Сири Женский", "Женский"
        ]
        
        if let femaleRU = voices.first(where: { v in
            v.language.hasPrefix("ru-RU") &&
            preferredFemaleNames.contains(where: { name in
                v.name.localizedCaseInsensitiveContains(name) ||
                v.identifier.localizedCaseInsensitiveContains(name)
            })
        }) {
            return femaleRU
        }
        
        // 3) Heuristic: pick the first ru-RU voice that is NOT a known male name
        // (Apple may add male Russian voices in future OS versions)
        let knownMaleNames = ["Yuri", "Юрий", "Male", "Сири Мужской", "Мужской"]
        
        if let heuristicRU = voices.first(where: { v in
            v.language.hasPrefix("ru-RU") &&
            !knownMaleNames.contains(where: { name in
                v.name.localizedCaseInsensitiveContains(name) ||
                v.identifier.localizedCaseInsensitiveContains(name)
            })
        }) {
            return heuristicRU
        }
        
        // 4) Nothing matched; caller will fallback to ru-RU default
        return nil
    }

}
