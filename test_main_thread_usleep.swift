import Foundation

@MainActor
func test() {
    print("Start")
    usleep(100_000)
    print("End")
}

test()
