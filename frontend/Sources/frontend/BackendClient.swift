import Foundation
import Combine

struct AudioDevice: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let maxOutputChannels: Int
    let isDefault: Bool
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct Track: Codable, Identifiable, Hashable {
    let id: Int
    let playlistId: Int
    let filePath: String
    let title: String
    let duration: Double
    let trackOrder: Int
}

struct Schedule: Codable, Identifiable, Hashable {
    let id: Int
    let playlistId: Int
    let playlistName: String
    let daysOfWeek: String
    let timeOfDay: String
    let isActive: Int // 1 = active, 0 = inactive
}

struct PlaybackStatus: Codable {
    let playlistId: Int?
    let playlistName: String?
    let currentTrack: Track?
    let trackIndex: Int
    let totalTracks: Int
    let isPlaying: Bool
    let isPaused: Bool
    let currentTime: Double
    let duration: Double
    let progress: Double
    let volume: Double
    let deviceId: Int?
}

class BackendClient: ObservableObject {
    static let shared = BackendClient()
    private let baseURL = "http://127.0.0.1:18088"
    
    @Published var isConnected = false
    @Published var devices: [AudioDevice] = []
    @Published var playlists: [Playlist] = []
    @Published var selectedPlaylistTracks: [Track] = []
    @Published var schedules: [Schedule] = []
    @Published var status: PlaybackStatus?
    @Published var isDownloading = false
    @Published var downloadError: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    
    private init() {
        // Start polling the playback status immediately
        startPolling()
    }
    
    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.fetchStatus()
        }
    }
    
    func stopPolling() {
        pollTimer?.invalidate()
    }
    
    private func getJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    
    // --- API Calls ---
    
    func fetchStatus() {
        guard let url = URL(string: "\(baseURL)/playback/status") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: PlaybackStatus.self, decoder: getJSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure = completion {
                    self?.isConnected = false
                }
            }, receiveValue: { [weak self] status in
                self?.status = status
                self?.isConnected = true
            })
            .store(in: &cancellables)
    }
    
    func fetchDevices() {
        guard let url = URL(string: "\(baseURL)/devices") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [AudioDevice].self, decoder: getJSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] devices in
                self?.devices = devices
            })
            .store(in: &cancellables)
    }
    
    func setDevice(deviceId: Int) {
        guard let url = URL(string: "\(baseURL)/settings/device") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["device_id": deviceId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchStatus()
                }
            }
        }.resume()
    }
    
    func fetchPlaylists() {
        guard let url = URL(string: "\(baseURL)/playlists") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Playlist].self, decoder: getJSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] playlists in
                self?.playlists = playlists
            })
            .store(in: &cancellables)
    }
    
    func createPlaylist(name: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "\(baseURL)/playlists") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["name": name]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchPlaylists()
                    completion()
                }
            }
        }.resume()
    }
    
    func deletePlaylist(playlistId: Int) {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchPlaylists()
                }
            }
        }.resume()
    }
    
    func renamePlaylist(playlistId: Int, name: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["name": name]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchPlaylists()
                    completion()
                }
            }
        }.resume()
    }
    
    func fetchTracks(playlistId: Int) {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Track].self, decoder: getJSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] tracks in
                self?.selectedPlaylistTracks = tracks
            })
            .store(in: &cancellables)
    }
    
    func addTrack(playlistId: Int, filePath: String) {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["file_path": filePath]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchTracks(playlistId: playlistId)
                }
            }
        }.resume()
    }
    
    func deleteTrack(trackId: Int, playlistId: Int) {
        guard let url = URL(string: "\(baseURL)/tracks/\(trackId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchTracks(playlistId: playlistId)
                }
            }
        }.resume()
    }
    
    func reorderTracks(playlistId: Int, trackIds: [Int]) {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks/order") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["track_ids": trackIds]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchTracks(playlistId: playlistId)
                }
            }
        }.resume()
    }
    
    func fetchSchedules() {
        guard let url = URL(string: "\(baseURL)/schedules") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Schedule].self, decoder: getJSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] schedules in
                self?.schedules = schedules
            })
            .store(in: &cancellables)
    }
    
    func createSchedule(playlistId: Int, daysOfWeek: String, timeOfDay: String) {
        guard let url = URL(string: "\(baseURL)/schedules") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "playlist_id": playlistId,
            "days_of_week": daysOfWeek,
            "time_of_day": timeOfDay
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchSchedules()
                }
            }
        }.resume()
    }
    
    func deleteSchedule(scheduleId: Int) {
        guard let url = URL(string: "\(baseURL)/schedules/\(scheduleId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchSchedules()
                }
            }
        }.resume()
    }
    
    func toggleSchedule(scheduleId: Int, isActive: Bool) {
        guard let url = URL(string: "\(baseURL)/schedules/\(scheduleId)/toggle?is_active=\(isActive)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        
        URLSession.shared.dataTask(with: request) { [weak self] _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.fetchSchedules()
                }
            }
        }.resume()
    }
    
    // --- Controls & Playback Test Triggers ---
    
    func playPlaylist(playlistId: Int) {
        guard let url = URL(string: "\(baseURL)/playlists/\(playlistId)/play") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func testSchedule(scheduleId: Int) {
        guard let url = URL(string: "\(baseURL)/schedules/\(scheduleId)/test") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func togglePlayPause() {
        guard let status = status else { return }
        let endpoint = status.isPlaying ? "pause" : "resume"
        guard let url = URL(string: "\(baseURL)/playback/\(endpoint)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func stopPlayback() {
        guard let url = URL(string: "\(baseURL)/playback/stop") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func nextTrack() {
        guard let url = URL(string: "\(baseURL)/playback/next") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func previousTrack() {
        guard let url = URL(string: "\(baseURL)/playback/previous") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func setVolume(volume: Double) {
        guard let url = URL(string: "\(baseURL)/playback/volume") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["volume": volume]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func seek(progress: Double) {
        guard let url = URL(string: "\(baseURL)/playback/seek") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["progress": progress]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    struct PlaylistEntry: Codable, Identifiable {
        var id: String { title + uploader }
        let title: String
        let duration: Double
        let uploader: String
    }

    struct YoutubeInfoResponse: Codable {
        let status: String
        let title: String
        let is_playlist: Bool
        let thumbnail: String?
        let uploader: String?
        let duration: Double
        let available_resolutions: [Int]?
        let playlist_entries: [PlaylistEntry]?
    }
    
    func fetchYoutubeInfo(url: String, completion: @escaping (YoutubeInfoResponse?) -> Void) {
        guard let endpointUrl = URL(string: "\(baseURL)/youtube/info") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["url": url]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            do {
                let info = try JSONDecoder().decode(YoutubeInfoResponse.self, from: data)
                completion(info)
            } catch {
                completion(nil)
            }
        }.resume()
    }

    func downloadYoutube(url: String, audioOnly: Bool, formatType: String, quality: String, destinationDir: String?, playlistId: Int?, completion: @escaping (Bool) -> Void) {
        guard let endpointUrl = URL(string: "\(baseURL)/download") else { return }
        
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadError = nil
        }
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "url": url,
            "audio_only": audioOnly,
            "format_type": formatType,
            "quality": quality
        ]
        if let dest = destinationDir {
            body["destination_dir"] = dest
        }
        if let pid = playlistId {
            body["playlist_id"] = pid
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    self?.downloadError = error.localizedDescription
                    completion(false)
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                var serverError = "Server returned error \(httpResponse.statusCode)"
                if let data = data, let errMsg = String(data: data, encoding: .utf8) {
                    serverError = errMsg
                }
                DispatchQueue.main.async {
                    self?.downloadError = serverError
                    completion(false)
                }
                return
            }
            
            DispatchQueue.main.async {
                if let pid = playlistId {
                    self?.fetchTracks(playlistId: pid)
                }
                completion(true)
            }
        }.resume()
    }
}
