import Foundation

class InfluxDBService {
    // InfluxDB Configuration - UPDATE THESE VALUES
    private let url = "Update_Here"
    private let token = "Update_Here"
    private let org = "Update_Here"
    private let bucket = "Update_Here"
    
    // Async version for single shot upload
    func writeShotData(_ shot: TennisShot) async throws {
        try await uploadShotsAsync([shot])
    }
    
    // Async version for batch upload
    func uploadShotsAsync(_ shots: [TennisShot]) async throws {
        guard !shots.isEmpty else {
            throw NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No shots to upload"])
        }
        
        // Build line protocol data
        var lines: [String] = []
        
        for shot in shots {
            let timestamp = Int(shot.timestamp.timeIntervalSince1970 * 1_000_000_000) // nanoseconds
            let line = """
            tennis_shot,device=iOS_App,stroke_type=\(shot.stroke) \
            swing_speed_mph=\(shot.swing),\
            spin_dps=\(shot.spin) \
            \(timestamp)
            """
            lines.append(line)
        }
        
        let body = lines.joined(separator: "\n")
        
        // Create request
        let endpoint = "\(url)/api/v2/write?org=\(org)&bucket=\(bucket)&precision=ns"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        
        print("📤 Uploading \(shots.count) shots to InfluxDB...")
        
        // Send request using async/await
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            print("✅ Successfully uploaded \(shots.count) shots")
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Upload failed (\(httpResponse.statusCode)): \(errorMsg)")
            throw NSError(domain: "InfluxDB", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    func uploadShots(_ shots: [TennisShot], completion: @escaping (Result<Int, Error>) -> Void) {
        guard !shots.isEmpty else {
            completion(.failure(NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No shots to upload"])))
            return
        }
        
        // Build line protocol data
        var lines: [String] = []
        
        for shot in shots {
            let timestamp = Int(shot.timestamp.timeIntervalSince1970 * 1_000_000_000) // nanoseconds
            let line = """
            tennis_shot,device=iOS_App,stroke_type=\(shot.stroke) \
            swing_speed_mph=\(shot.swing),\
            spin_dps=\(shot.spin) \
            \(timestamp)
            """
            lines.append(line)
        }
        
        let body = lines.joined(separator: "\n")
        
        // Create request
        let endpoint = "\(url)/api/v2/write?org=\(org)&bucket=\(bucket)&precision=ns"
        guard let url = URL(string: endpoint) else {
            completion(.failure(NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        
        print("📤 Uploading \(shots.count) shots to InfluxDB...")
        
        // Send request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Upload error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "InfluxDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                print("✅ Successfully uploaded \(shots.count) shots")
                completion(.success(shots.count))
            } else {
                let errorMsg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                print("❌ Upload failed (\(httpResponse.statusCode)): \(errorMsg)")
                completion(.failure(NSError(domain: "InfluxDB", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
            }
        }.resume()
    }
}
