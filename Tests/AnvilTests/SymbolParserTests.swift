import XCTest
@testable import Anvil

final class SymbolParserTests: XCTestCase {

    // MARK: - Swift

    func testSwiftFunctionsAndTypes() {
        let source = """
        import Foundation

        public class MyApp {
            private var name: String = ""

            func doSomething() {
                print("hello")
            }

            static func create() -> MyApp {
                return MyApp()
            }
        }

        struct Config {
            let timeout: Int = 30
        }

        enum State {
            case idle
            case running
        }

        protocol Runnable {
            func run()
        }
        """
        let symbols = SymbolParser.parse(source: source, language: "swift")

        let names = symbols.map(\.name)
        XCTAssertTrue(names.contains("MyApp"), "Should find class MyApp")
        XCTAssertTrue(names.contains("doSomething"), "Should find func doSomething")
        XCTAssertTrue(names.contains("create"), "Should find static func create")
        XCTAssertTrue(names.contains("Config"), "Should find struct Config")
        XCTAssertTrue(names.contains("State"), "Should find enum State")
        XCTAssertTrue(names.contains("Runnable"), "Should find protocol Runnable")

        // Verify kinds
        let classSymbol = symbols.first { $0.name == "MyApp" }
        XCTAssertEqual(classSymbol?.kind, .class_)

        let funcSymbol = symbols.first { $0.name == "doSomething" }
        XCTAssertEqual(funcSymbol?.kind, .function)

        let structSymbol = symbols.first { $0.name == "Config" }
        XCTAssertEqual(structSymbol?.kind, .struct_)

        let enumSymbol = symbols.first { $0.name == "State" }
        XCTAssertEqual(enumSymbol?.kind, .enum_)

        let protoSymbol = symbols.first { $0.name == "Runnable" }
        XCTAssertEqual(protoSymbol?.kind, .protocol_)
    }

    func testSwiftLineNumbers() {
        let source = """
        struct Foo {
            func bar() {}
        }
        """
        let symbols = SymbolParser.parse(source: source, language: "swift")

        let foo = symbols.first { $0.name == "Foo" }
        XCTAssertEqual(foo?.line, 1)

        let bar = symbols.first { $0.name == "bar" }
        XCTAssertEqual(bar?.line, 2)
    }

    func testSwiftNestedDepth() {
        let source = """
        class Outer {
            struct Inner {
                func method() {}
            }
        }
        """
        let symbols = SymbolParser.parse(source: source, language: "swift")

        let outer = symbols.first { $0.name == "Outer" }
        XCTAssertEqual(outer?.depth, 0)

        let inner = symbols.first { $0.name == "Inner" }
        XCTAssertEqual(inner?.depth, 1)

        let method = symbols.first { $0.name == "method" }
        XCTAssertEqual(method?.depth, 2)
    }

    // MARK: - TypeScript

    func testTypeScriptSymbols() {
        let source = """
        export class UserService {
            async getUser(id: string): Promise<User> {
                return db.find(id);
            }
        }

        export interface User {
            id: string;
            name: string;
        }

        export type UserId = string;

        export enum Role {
            Admin,
            User,
        }

        export function createApp() {
            return new App();
        }

        export const handler = async (req: Request) => {
            return new Response();
        };
        """
        let symbols = SymbolParser.parse(source: source, language: "typescript")

        let names = symbols.map(\.name)
        XCTAssertTrue(names.contains("UserService"), "Should find class")
        XCTAssertTrue(names.contains("User"), "Should find interface")
        XCTAssertTrue(names.contains("UserId"), "Should find type alias")
        XCTAssertTrue(names.contains("Role"), "Should find enum")
        XCTAssertTrue(names.contains("createApp"), "Should find function")
        XCTAssertTrue(names.contains("handler"), "Should find arrow function")
    }

    // MARK: - Python

    func testPythonSymbols() {
        let source = """
        class Animal:
            def __init__(self, name):
                self.name = name

            def speak(self):
                pass

        class Dog(Animal):
            def speak(self):
                return "Woof"

        async def fetch_data(url):
            pass

        def helper():
            pass
        """
        let symbols = SymbolParser.parse(source: source, language: "python")

        let names = symbols.map(\.name)
        XCTAssertTrue(names.contains("Animal"), "Should find class Animal")
        XCTAssertTrue(names.contains("Dog"), "Should find class Dog")
        XCTAssertTrue(names.contains("__init__"), "Should find __init__")
        XCTAssertTrue(names.contains("speak"), "Should find method speak")
        XCTAssertTrue(names.contains("fetch_data"), "Should find async function")
        XCTAssertTrue(names.contains("helper"), "Should find helper function")
    }

    // MARK: - Go

    func testGoSymbols() {
        let source = """
        type Server struct {
            Port int
        }

        type Handler interface {
            Handle(r Request) Response
        }

        func NewServer(port int) *Server {
            return &Server{Port: port}
        }

        func (s *Server) Start() error {
            return nil
        }
        """
        let symbols = SymbolParser.parse(source: source, language: "go")

        let names = symbols.map(\.name)
        XCTAssertTrue(names.contains("Server"), "Should find struct Server")
        XCTAssertTrue(names.contains("Handler"), "Should find interface Handler")
        XCTAssertTrue(names.contains("NewServer"), "Should find function NewServer")
        XCTAssertTrue(names.contains("Start"), "Should find method Start")

        let server = symbols.first { $0.name == "Server" }
        XCTAssertEqual(server?.kind, .struct_)

        let handler = symbols.first { $0.name == "Handler" }
        XCTAssertEqual(handler?.kind, .interface)

        let start = symbols.first { $0.name == "Start" }
        XCTAssertEqual(start?.kind, .method)
    }

    // MARK: - Rust

    func testRustSymbols() {
        let source = """
        pub struct Config {
            pub name: String,
        }

        pub enum Error {
            NotFound,
            Internal,
        }

        pub trait Service {
            fn process(&self) -> Result<()>;
        }

        pub async fn serve(config: Config) -> Result<()> {
            Ok(())
        }

        fn helper() {}
        """
        let symbols = SymbolParser.parse(source: source, language: "rust")

        let names = symbols.map(\.name)
        XCTAssertTrue(names.contains("Config"), "Should find struct Config")
        XCTAssertTrue(names.contains("Error"), "Should find enum Error")
        XCTAssertTrue(names.contains("Service"), "Should find trait Service")
        XCTAssertTrue(names.contains("serve"), "Should find async fn serve")
        XCTAssertTrue(names.contains("helper"), "Should find fn helper")
    }

    // MARK: - Edge Cases

    func testEmptySource() {
        let symbols = SymbolParser.parse(source: "", language: "swift")
        XCTAssertTrue(symbols.isEmpty)
    }

    func testNilLanguage() {
        let symbols = SymbolParser.parse(source: "func foo() {}", language: nil)
        XCTAssertTrue(symbols.isEmpty)
    }

    func testUnsupportedLanguage() {
        let symbols = SymbolParser.parse(source: "something", language: "brainfuck")
        XCTAssertTrue(symbols.isEmpty)
    }

    func testCommentsSkipped() {
        let source = """
        // func notAFunction() {}
        # class NotAClass:
        func realFunction() {}
        """
        let symbols = SymbolParser.parse(source: source, language: "swift")
        let names = symbols.map(\.name)
        XCTAssertFalse(names.contains("notAFunction"))
        XCTAssertTrue(names.contains("realFunction"))
    }
}
