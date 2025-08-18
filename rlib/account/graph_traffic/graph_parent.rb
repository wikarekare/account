# Uber class for common methods
# Uber class for common methods
class Graph_Parent
  attr_reader :images
  attr_accessor :debug

  def initialize(*_args)
    @debug = false ######
    @images = ''
  end

  def adsl_ip?(address)
    return address == EXTERNAL5 || address == EXTERNAL6 || address == EXTERNAL7
  end

  def ignore?(dest_address)
    dest_ip = dest_address.split('.')
    return ( adsl_ip?(dest_address) ||
             dest_ip[0] == '10' ||  # Destination is 10.0.0.0/8
             ( dest_ip[0] == '192' && dest_ip[1] == '168' ) || # Destination is 192.168.0.0/16
             ( dest_ip[0] == '100' && dest_ip[1] == '64' ) || # Destination is 100.64.0.0/16
             ( dest_ip[0] == '172' && dest_ip[1].to_i.between(16, 31) ) || # Destination is 172.16.0.0/12
             dest_address == '255.255.255.255' || # Broadcast
             dest_ip[0].to_i.between(224, 239)    # Destination is multicast
           )
  end
end
