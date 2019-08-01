import Cocoa
import Foundation

let baseURL = "http://localhost:8080"

enum APIError: Error {
    case invalidBody
    case invalidEndpoint
    case invalidURL
    case emptyData
    case invalidJSON
    case invalidResponse
    case statusCode(Int)
}

struct User: Codable {
    let name: String
    let email: String
    let password: String
    let verifyPassword: String
}

// We'll use this extension to quicly generate some user for our requests
extension User {
    init(id: Int) {
        self.name = "user\(id)"
        self.email = "user\(id)@example.com"
        self.password = "password\(id)"
        self.verifyPassword = "password\(id)"
    }
}

// Basic API client using dataTask
// From now on, we'll use the suffix OLD to indicate the API Client implemented with dataTask
func createUserOLD(user: User, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
    ]
    let encoder = JSONEncoder()
    guard let postData = try? encoder.encode(user) else {
        completion(nil,nil, APIError.invalidBody)
        return
    }
    guard let url = URL(string: baseURL + "/users" ) else {
        completion(nil,nil, APIError.invalidEndpoint)
        return
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    request.httpBody = postData as Data
    
    let session = URLSession.shared
    let dataTask = session.dataTask(with: request as URLRequest, completionHandler: completion)
    dataTask.resume()
}


// Basic usage of the dataTask client
createUserOLD(user: User(id:2)) { (data, response, error) in
    if let data = data,
            let string = String(data: data, encoding: .utf8) {
            print(string)
    } else {
            print(" - No data")
    }
    //print(response ?? "")
    print(error ?? "")
}


// Part 2
import Combine

// With Combine we return a DataTaskPublisher instead of using the completion handler of the DataTask
func postUser(user: User) throws -> URLSession.DataTaskPublisher {
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
    ]
    let encoder = JSONEncoder()
    guard let postData = try? encoder.encode(user) else {
        throw APIError.invalidBody
    }
    guard let url = URL(string: baseURL + "/users" ) else {
        throw APIError.invalidEndpoint
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    request.httpBody = postData as Data
    
    let session = URLSession.shared
    return session.dataTaskPublisher(for: request)
}

// Basic usage of the API client with dataTaskPublisher

// Create a DataTaskPublisher
let postUserPublisher = try? postUser(user: User(id:3))

// Use the sink Subscriber to complete the Publisher -> Subscriber pipeline
let cancellable = postUserPublisher?.sink(receiveCompletion: { (completion) in
    switch completion {
    case .failure(let error):
        print(error)
    case .finished:
        print("DONE - postUserPublisher")
    }
}, receiveValue: { (data, response) in
    if let string = String(data: data, encoding: .utf8) {
        print(string)
    }
})

// Part 3

// In a real world App we want to decode our JSON data response into a Codable Object

struct CreateUserResponse: Codable {
    let id: Int
    let email: String
    let name: String
}


// Decoding CreateUserResponse inside a DataTask API client
createUserOLD(user: User(id: 4)) { (data, response, error) in

    let decoder = JSONDecoder()
    do {
        if let data = data {
            let response =  try decoder.decode(CreateUserResponse.self, from: data)
            print(response)
        } else {
            print(APIError.emptyData)
        }
    } catch (let error) {
        print(error)
    }
}


// Decoding CreateUserResponse inside the pipeline
// Note: For simplicity, we are not considering the response.statusCode

let postUser5Publisher = try? postUser(user: User(id: 5))

let decoder = JSONDecoder()
let cancellable2 = postUser5Publisher?
    .map { $0.data }
    .decode(type: CreateUserResponse.self, decoder: decoder)
    .sink(receiveCompletion: { (completion) in
        switch completion {
        case .failure(let error):
            print(error)
        case .finished:
            print("DONE - postUser5Publisher")
        }
    }, receiveValue: { user in
        print(user)
    })


// Part 4

// Refactoring of the URLRequest with dataTask avoing Throws using fatalError
func buildCreateUserURLRequest(user: User) -> URLRequest {
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
    ]
    let encoder = JSONEncoder()
    guard let postData = try? encoder.encode(user) else {
        fatalError("APIError.invalidBody")
    }
    guard let url = URL(string: baseURL + "/users" ) else {
        fatalError("APIError.invalidEndpoint")
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    request.httpBody = postData as Data
    return request
}

// Our old API client dataTask refactoring
func createUserOLDRefactoring(user: User, session: URLSession = URLSession.shared, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
    let request = buildCreateUserURLRequest(user: user)
    let dataTask = session.dataTask(with: request as URLRequest, completionHandler: completion)
    dataTask.resume()
}

// Reuse your refactored old API client to implement a Publisher
func createUserPublisher(user: User, session: URLSession = URLSession.shared) -> Future<CreateUserResponse, Error> {
    
    let future = Future<CreateUserResponse, Error>.init { (promise) in
    
        let completion: (Data?, URLResponse?, Error?) -> () = { (data, response, error) in
            
            //Response Validation
            guard let httpResponse = response as? HTTPURLResponse else {
                promise(.failure(APIError.invalidResponse))
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                promise(.failure(APIError.statusCode(httpResponse.statusCode)))
                return
            }
            
            // Decoding data
            let decoder = JSONDecoder()
            do {
                if let data = data {
                    let response =  try decoder.decode(CreateUserResponse.self, from: data)
                    promise(.success(response))
                } else {
                    promise(.failure(APIError.emptyData))
                }
            } catch (let error) {
                promise(.failure(error))
            }
        }
        
        //Execute the request
        createUserOLDRefactoring(user: user, session: session, completion: completion)
    }
    return future
}


// Usage of the refactored old API client Publisher

let createUser6Publisher = createUserPublisher(user: User(id: 6))

let cancellable3 = createUser6Publisher
    .sink(receiveCompletion: { (completion) in
        switch completion {
        case .failure(let error):
            print(error)
        case .finished:
            print("DONE - createUser6Publisher")
        }
    }, receiveValue: { reponse in
        print(reponse)
    })


// Completing the API with Combine and dataTaskPublisher

// POST - Login
func buildLoginRequest(email: String, password: String) -> URLRequest {
    
    
    let loginString = String(format: "%@:%@", email, password)
    let loginData: Data = loginString.data(using: .utf8)!
    let base64LoginString = loginData.base64EncodedString()
    
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
        "Authorization": "Basic \(base64LoginString)"
    ]
    guard let url = URL(string: baseURL + "/login" ) else {
        fatalError("APIError.invalidEndpoint")
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    return request
}

func postLogin(email: String,password: String, session: URLSession = URLSession.shared) -> URLSession.DataTaskPublisher {
    let request = buildLoginRequest(email: email, password: password)
    return session.dataTaskPublisher(for: request)
}

//Todo API implementation with dataTaskPublisher
struct Todo: Codable {
    let id: Int?
    let title: String
}

// POST - todos
func buildPostTodoRequest(authToken: String, body: Todo) -> URLRequest {
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
        "Authorization": "Bearer \(authToken)"
    ]
    let encoder = JSONEncoder()
    guard let postData = try? encoder.encode(body) else {
        fatalError("APIError.invalidBody")
    }
    guard let url = URL(string: baseURL + "/todos" ) else {
        fatalError("APIError.invalidEndpoint")
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    request.httpBody = postData
    return request
}

func postTodo(authToken: String, body: Todo, session: URLSession = URLSession.shared) -> URLSession.DataTaskPublisher {
    let request = buildPostTodoRequest(authToken: authToken, body: body)
    return session.dataTaskPublisher(for: request)
}

// GET - todos
func buildGetTodoRequest(authToken: String) -> URLRequest {
    
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
        "Authorization": "Bearer \(authToken)"
    ]
    guard let url = URL(string: baseURL + "/todos" ) else {
        fatalError("APIError.invalidEndpoint")
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "GET"
    request.allHTTPHeaderFields = headers
    return request
}

func getTodo(authToken: String, session: URLSession = URLSession.shared) -> URLSession.DataTaskPublisher {
    let request = buildGetTodoRequest(authToken: authToken)
    return session.dataTaskPublisher(for: request)
}

// DELETE - todos
func buildDeleteTodoRequest(authToken: String, id: Int) -> URLRequest {
    
    let headers = [
        "Content-Type": "application/json",
        "cache-control": "no-cache",
        "Authorization": "Bearer \(authToken)"
    ]
    guard let url = URL(string: baseURL + "/todos/\(id)" ) else {
        fatalError("APIError.invalidEndpoint")
    }
    var request = URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 10.0)
    request.httpMethod = "DELETE"
    request.allHTTPHeaderFields = headers
    return request
}


func deleteTodo(authToken: String, id: Int, session: URLSession = URLSession.shared) -> URLSession.DataTaskPublisher {
    let request = buildDeleteTodoRequest(authToken: authToken, id: id)
    return session.dataTaskPublisher(for: request)
}

// Use of the dataTaskPublisher API to implement Publisher with the decoded data
struct Token: Codable {
    let string: String
}

// We'll use the following function to validate our dataTaskPublisher output in the pipeline
func validate(_ data: Data, _ response: URLResponse) throws -> Data {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
        throw APIError.statusCode(httpResponse.statusCode)
    }
    return data
}

func create(user: User) -> AnyPublisher<CreateUserResponse, Error>? {
    return try? postUser(user: user)
        .tryMap{ try validate($0.data, $0.response) }
        .decode(type: CreateUserResponse.self, decoder: JSONDecoder())
        .eraseToAnyPublisher()
}
        
func login(email: String, password: String) -> AnyPublisher<Token, Error> {
    return postLogin(email: email, password: password)
            .tryMap{ try validate($0.data, $0.response) }
            .decode(type: Token.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
}

func postTodo(authToken: String, todo: Todo) -> AnyPublisher<Todo, Error> {
    return  postTodo(authToken: authToken, body: todo)
            .tryMap{ try validate($0.data, $0.response) }
            .decode(type: Todo.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
}

func getTodo(authToken: String) -> AnyPublisher<[Todo], Error> {
    return getTodo(authToken: authToken)
            .tryMap{ try validate($0.data, $0.response) }
            .decode(type: [Todo].self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
}

func deleteTodo(authToken: String, id: Int) -> AnyPublisher<Todo, Error> {
    return deleteTodo(authToken: authToken, id: id)
            .tryMap{ try validate($0.data, $0.response) }
            .decode(type: Todo.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
}
    
//Let's use our brand new Publishers

let todoList = [Todo(id: nil, title: "Learn Composite"),
                Todo(id: nil, title: "Learn SwiftUI")]


// use login to get the Bearer Token
let cancellableLogin = login(email: "user2@example.com", password: "password2")
    .sink(receiveCompletion: { (completion) in
        switch completion {
        case .failure(let error):
            print(error)
        case .finished:
            print("BEARER TOKEN")
        }
    }, receiveValue: { response in
        print(response)
    })


// Combining login and postTodo in a single call
func post(email: String, password: String, todo: Todo) -> AnyPublisher<Todo, Error>? {
    return login(email: email, password: password)
        .map {  token -> String in
            return token.string
        }
        .flatMap { (token) -> AnyPublisher<Todo, Error> in
            return postTodo(authToken: token, todo: todoList[1])
        }
        .eraseToAnyPublisher()
}

let cancellablePost = post(email: "user2@example.com", password: "password2", todo: todoList[0])?
    .sink(receiveCompletion: { (completion) in
        switch completion {
        case .failure(let error):
            print(error)
        case .finished:
            print("GET - DONE")
        }
    }, receiveValue: { response in
        print(response)
    })

    

