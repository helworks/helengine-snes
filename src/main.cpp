#include "platform/snes/SuperNintendoBootHost.hpp"

/// Program entry after the SDK crt0 has switched to native mode and cleared RAM.
int main() {
    helengine::snes::SuperNintendoBootHost host;
    return host.Run();
}
