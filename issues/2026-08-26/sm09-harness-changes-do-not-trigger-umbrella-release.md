# SM-09 harness changes must trigger the umbrella release

The deploy publication workflow omitted the private-registry lifecycle harness
from its push path filters. A mandatory gate fix could therefore merge without
starting the publish-to-umbrella workflow chain.
