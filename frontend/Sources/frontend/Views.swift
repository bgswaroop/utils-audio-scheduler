import SwiftUI
import AppKit

// MARK: - Visual Effect Blur Helper
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Time/Duration Helpers
func formatDuration(_ seconds: Double) -> String {
    guard !seconds.isNaN && seconds.isFinite else { return "0:00" }
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

func formatWeekdays(_ daysStr: String) -> String {
    let days = daysStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    let matchedNames = days.compactMap { d -> String? in
        guard d >= 0 && d < 7 else { return nil }
        return weekdayNames[d]
    }
    if matchedNames.count == 7 { return "Every Day" }
    if matchedNames.count == 5 && days.contains(0) && days.contains(1) && days.contains(2) && days.contains(3) && days.contains(4) {
        return "Weekdays"
    }
    if matchedNames.count == 2 && days.contains(5) && days.contains(6) {
        return "Weekends"
    }
    return matchedNames.isEmpty ? "None" : matchedNames.joined(separator: ", ")
}

// MARK: - Main Layout View
struct MainView: View {
    @StateObject private var client = BackendClient.shared
    @State private var selectedTab: String = "playlists"
    
    var body: some View {
        HSplitView {
            // Sidebar Navigation
            SidebarView(selectedTab: $selectedTab)
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                .layoutPriority(1)
            
            // Main Panel View
            VStack(spacing: 0) {
                // Header Connection Status Indicator
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(client.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(client.isConnected ? "Engine Connected" : "Engine Disconnected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .cornerRadius(12)
                }
                .padding(.top, 40) // Spacing below window buttons
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                
                Divider()
                    .opacity(0.3)
                
                // Active Panel Content
                Group {
                    switch selectedTab {
                    case "playlists":
                        PlaylistsView()
                    case "schedules":
                        SchedulesView()
                    case "settings":
                        SettingsView()
                    default:
                        PlaylistsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 90) // Ensure content scrolls above the bottom playback bar
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity)
            .layoutPriority(2)
        }
        .overlay(
            VStack {
                Spacer()
                MediaBarView()
            }
        )
        .onAppear {
            client.fetchPlaylists()
            client.fetchSchedules()
            client.fetchDevices()
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedTab: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Window Spacer
            Spacer()
                .frame(height: 50)
            
            // Title
            Text("Library")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            
            // Navigation Links
            VStack(spacing: 4) {
                SidebarItem(title: "Playlists", icon: "music.note.list", isSelected: selectedTab == "playlists") {
                    selectedTab = "playlists"
                }
                SidebarItem(title: "Schedules", icon: "calendar.badge.clock", isSelected: selectedTab == "schedules") {
                    selectedTab = "schedules"
                    BackendClient.shared.fetchSchedules()
                }
                SidebarItem(title: "Settings", icon: "gearshape", isSelected: selectedTab == "settings") {
                    selectedTab = "settings"
                    BackendClient.shared.fetchDevices()
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
        .background(VisualEffectView())
    }
}

struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .accentColor)
                    .frame(width: 18, height: 18)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Playlists View
struct PlaylistsView: View {
    @StateObject private var client = BackendClient.shared
    @State private var selectedPlaylist: Playlist?
    @State private var showingCreateSheet = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        HSplitView {
            // Playlists List
            VStack(spacing: 0) {
                HStack {
                    Text("Playlists")
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .padding(6)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Create New Playlist")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                List(client.playlists, id: \.id, selection: $selectedPlaylist) { playlist in
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                        Text(playlist.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        
                        // Delete Playlist Action
                        Button(action: {
                            client.deletePlaylist(playlistId: playlist.id)
                            if selectedPlaylist?.id == playlist.id {
                                selectedPlaylist = nil
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .help("Delete Playlist")
                    }
                    .padding(.vertical, 4)
                    .tag(playlist)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
            
            // Playlist Tracks Detail
            VStack(spacing: 0) {
                if let playlist = selectedPlaylist {
                    PlaylistDetailView(playlist: playlist)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Select a playlist to view tracks")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingCreateSheet) {
            VStack(spacing: 20) {
                Text("New Playlist")
                    .font(.system(size: 16, weight: .bold))
                
                TextField("Playlist Name", text: $newPlaylistName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        showingCreateSheet = false
                        newPlaylistName = ""
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Create") {
                        if !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty {
                            client.createPlaylist(name: newPlaylistName) {
                                newPlaylistName = ""
                                showingCreateSheet = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 300)
        }
        .onAppear {
            client.fetchPlaylists()
        }
    }
}

// MARK: - Playlist Detail View (Tracks)
struct PlaylistDetailView: View {
    let playlist: Playlist
    @StateObject private var client = BackendClient.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Info Card
            HStack(spacing: 24) {
                // Playlist Cover Accent
                LinearGradient(colors: [Color.pink, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 100, height: 100)
                    .cornerRadius(12)
                    .shadow(radius: 6)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.name)
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("\(client.selectedPlaylistTracks.count) Songs • Total duration \(formatDuration(client.selectedPlaylistTracks.map(\.duration).reduce(0, +)))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        // Play / Test Now Button
                        Button(action: {
                            client.playPlaylist(playlistId: playlist.id)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Test Now")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        // Add Tracks Button
                        Button(action: selectAndAddTracks) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add Music File")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
            .padding(24)
            
            Divider()
                .opacity(0.3)
            
            // Tracks list
            if client.selectedPlaylistTracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("This playlist has no tracks.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Button("Select Files") {
                        selectAndAddTracks()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Table Header
                    HStack(spacing: 0) {
                        Text("#")
                            .frame(width: 30, alignment: .leading)
                        Text("Title")
                            .frame(minWidth: 200, alignment: .leading)
                        Spacer()
                        Text("Duration")
                            .frame(width: 80, alignment: .trailing)
                        Text("")
                            .frame(width: 40)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    
                    ForEach(Array(client.selectedPlaylistTracks.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 0) {
                            Text("\(index + 1)")
                                .frame(width: 30, alignment: .leading)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(track.filePath)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(minWidth: 200, alignment: .leading)
                            
                            Spacer()
                            
                            Text(formatDuration(track.duration))
                                .frame(width: 80, alignment: .trailing)
                                .foregroundColor(.secondary)
                            
                            // Delete Button
                            HStack {
                                Button(action: {
                                    client.deleteTrack(trackId: track.id, playlistId: playlist.id)
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove Track")
                            }
                            .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(client.status?.currentTrack?.id == track.id ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            client.fetchTracks(playlistId: playlist.id)
        }
        .onChange(of: playlist) { newPlaylist in
            client.fetchTracks(playlistId: newPlaylist.id)
        }
    }
    
    private func selectAndAddTracks() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Define common audio formats
        panel.allowedFileTypes = ["mp3", "wav", "m4a", "flac", "ogg", "aac"]
        panel.message = "Choose audio files to add to '\(playlist.name)'"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                client.addTrack(playlistId: playlist.id, filePath: url.path)
            }
        }
    }
}

// MARK: - Schedules View
struct SchedulesView: View {
    @StateObject private var client = BackendClient.shared
    
    @State private var selectedPlaylistId: Int = -1
    @State private var hour: Int = 12
    @State private var minute: Int = 0
    @State private var selectedDays: Set<Int> = []
    
    let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Schedules")
                .font(.system(size: 24, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)
            
            Text("Define exact hours and days of the week for automated audio events.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            
            // New Schedule Creation Section
            VStack(alignment: .leading, spacing: 14) {
                Text("Create New Automated Schedule")
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 16) {
                    // Playlist Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Playlist")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Picker("", selection: $selectedPlaylistId) {
                            Text("Select Playlist...").tag(-1)
                            ForEach(client.playlists) { p in
                                Text(p.name).tag(p.id as Int)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    
                    // Time Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Execution Time")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Picker("", selection: $hour) {
                                ForEach(0..<24) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 50)
                            
                            Text(":")
                                .font(.system(size: 14, weight: .bold))
                            
                            Picker("", selection: $minute) {
                                ForEach(0..<60) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 50)
                        }
                    }
                    
                    Spacer()
                    
                    // Add Schedule Button
                    Button(action: addSchedule) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Schedule")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selectedPlaylistId == -1 || selectedDays.isEmpty ? Color.gray : Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPlaylistId == -1 || selectedDays.isEmpty)
                }
                
                // Days selection checkboxes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trigger Days")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<7) { dayIndex in
                            let dayName = weekdays[dayIndex]
                            let isSelected = selectedDays.contains(dayIndex)
                            
                            Button(action: {
                                if isSelected {
                                    selectedDays.remove(dayIndex)
                                } else {
                                    selectedDays.insert(dayIndex)
                                }
                            }) {
                                Text(dayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            
            Divider()
                .opacity(0.3)
                
            // Schedules List
            List {
                HStack(spacing: 0) {
                    Text("Playlist")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 150, alignment: .leading)
                    
                    Text("Trigger Days")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 200, alignment: .leading)
                    
                    Text("Time")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .center)
                    
                    Text("Status")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .center)
                    
                    Spacer()
                    Text("Actions")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                
                if client.schedules.isEmpty {
                    Text("No schedules created yet.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(client.schedules) { sched in
                        HStack(spacing: 0) {
                            Text(sched.playlistName)
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 150, alignment: .leading)
                            
                            Text(formatWeekdays(sched.daysOfWeek))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 200, alignment: .leading)
                            
                            Text(sched.timeOfDay)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(width: 80, alignment: .center)
                            
                            // Active Switch (Toggle)
                            Toggle("", isOn: Binding(
                                get: { sched.isActive == 1 },
                                set: { client.toggleSchedule(scheduleId: sched.id, isActive: $0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .frame(width: 60, alignment: .center)
                            
                            Spacer()
                            
                            // Actions: Test Now / Delete
                            HStack(spacing: 12) {
                                Button(action: {
                                    client.testSchedule(scheduleId: sched.id)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "play.fill")
                                        Text("Test")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Test Playback Immediately")
                                
                                Button(action: {
                                    client.deleteSchedule(scheduleId: sched.id)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Delete Schedule")
                            }
                            .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        )
                    }
                }
            }
            .listStyle(.plain)
            .padding(.horizontal, 12)
        }
        .onAppear {
            client.fetchSchedules()
            client.fetchPlaylists()
        }
    }
    
    private func addSchedule() {
        guard selectedPlaylistId != -1 && !selectedDays.isEmpty else { return }
        
        let daysString = selectedDays.sorted().map(String.init).joined(separator: ",")
        let timeString = String(format: "%02d:%02d", hour, minute)
        
        client.createSchedule(playlistId: selectedPlaylistId, daysOfWeek: daysString, timeOfDay: timeString)
        
        // Reset selections
        selectedDays = []
        selectedPlaylistId = -1
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var client = BackendClient.shared
    @State private var selectedDeviceIndex: Int = -1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
            
            // Audio Core Routing settings
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                    Text("Audio Output Device Control")
                        .font(.system(size: 14, weight: .bold))
                }
                
                Text("Select the hardware device target (e.g. Multi-Output Device) to route music. System alert and notification sound tracks will continue to use the macOS default main speaker.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                if client.devices.isEmpty {
                    Text("No output devices listed or scanner failing.")
                        .foregroundColor(.red)
                } else {
                    Picker("Target CoreAudio Output", selection: $selectedDeviceIndex) {
                        Text("Default System Audio Device").tag(-1)
                        ForEach(client.devices) { device in
                            Text("\(device.name) (\(device.maxOutputChannels) ch)").tag(device.id as Int)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 400)
                    .onChange(of: selectedDeviceIndex) { newIndex in
                        client.setDevice(deviceId: newIndex)
                    }
                }
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            
            // Engine status & diagnostics
            VStack(alignment: .leading, spacing: 12) {
                Text("Diagnostics & Engine State")
                    .font(.system(size: 14, weight: .bold))
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(client.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(client.isConnected ? "FastAPI Local REST Engine Running" : "FastAPI Backend Offline")
                        .font(.system(size: 13, weight: .medium))
                    
                    if !client.isConnected {
                        Button("Re-connect") {
                            client.fetchStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                if let status = client.status {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Playlist: \(status.playlistName ?? "None")")
                        Text("Song Playing: \(status.currentTrack?.title ?? "Idle")")
                        Text("Current Volume Setting: \(Int(status.volume * 100))%")
                        Text("Selected CoreAudio Index: \(status.deviceId == nil ? "Default System (-1)" : String(status.deviceId!))")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding(24)
        .onAppear {
            client.fetchDevices()
            client.fetchStatus()
            
            // Set local initial picker state
            if let targetId = client.status?.deviceId {
                selectedDeviceIndex = targetId
            } else {
                selectedDeviceIndex = -1
            }
        }
        .onChange(of: client.status?.deviceId) { newId in
            if let newId = newId {
                selectedDeviceIndex = newId
            } else {
                selectedDeviceIndex = -1
            }
        }
    }
}

// MARK: - Bottom Floating Media Bar
struct MediaBarView: View {
    @StateObject private var client = BackendClient.shared
    @State private var sliderVal: Double = 0.0
    @State private var isSeeking = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.3)
            
            HStack(spacing: 24) {
                // Left Now Playing Track Info
                HStack(spacing: 12) {
                    if let track = client.status?.currentTrack {
                        // Tiny cover artwork representation
                        LinearGradient(colors: [Color.pink, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: 48, height: 48)
                            .cornerRadius(6)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(client.status?.playlistName ?? "Unknown Playlist")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.secondary)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not Playing")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("No Schedule Events Active")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
                .frame(width: 250, alignment: .leading)
                
                // Center Controls and Timeline
                VStack(spacing: 6) {
                    // Playback Action Buttons
                    HStack(spacing: 20) {
                        // Previous Button
                        Button(action: { client.previousTrack() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(client.status?.playlistId == nil)
                        
                        // Play/Pause Button
                        Button(action: { client.togglePlayPause() }) {
                            Image(systemName: (client.status?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .frame(width: 32, height: 32)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(client.status?.playlistId == nil)
                        
                        // Stop Button
                        Button(action: { client.stopPlayback() }) {
                            Image(systemName: "square.fill")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(client.status?.playlistId == nil)
                        
                        // Next Button
                        Button(action: { client.nextTrack() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(client.status?.playlistId == nil)
                    }
                    
                    // Slider Seekbar
                    HStack(spacing: 8) {
                        Text(formatDuration(getCurrentTime()))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .leading)
                        
                        Slider(value: Binding(
                            get: { getProgress() },
                            set: { val in
                                sliderVal = val
                                isSeeking = true
                            }
                        ), in: 0.0...1.0, onEditingChanged: { editing in
                            if !editing {
                                client.seek(progress: sliderVal)
                                isSeeking = false
                            }
                        })
                        .labelsHidden()
                        .disabled(client.status?.playlistId == nil || (client.status?.duration ?? 0) <= 0)
                        
                        Text(formatDuration(client.status?.duration ?? 0.0))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    .frame(width: 450)
                }
                
                Spacer()
                
                // Right Side Volume Controls
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { client.status?.volume ?? 0.5 },
                        set: { client.setVolume(volume: $0) }
                    ), in: 0.0...1.0)
                    .labelsHidden()
                    .frame(width: 100)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.secondary)
                }
                .frame(width: 150, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
        .frame(height: 90)
    }
    
    private func getCurrentTime() -> Double {
        if isSeeking {
            return sliderVal * (client.status?.duration ?? 0.0)
        }
        return client.status?.currentTime ?? 0.0
    }
    
    private func getProgress() -> Double {
        if isSeeking {
            return sliderVal
        }
        return client.status?.progress ?? 0.0
    }
}
