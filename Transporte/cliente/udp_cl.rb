require "#{File.expand_path(__FILE__)}/../../tcp"

if ARGV.length < 3 then
    puts "Parâmetros insuficientes!"
    exit
end 

app_port  = ARGV[0].to_i
fscl_port = ARGV[1].to_i
fssr_port = ARGV[2].to_i

socket = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
sockaddr = Socket.sockaddr_in(app_port, 'localhost')
socket.bind(sockaddr)
socket.listen(10)

while true

    puts "Esperando dados da aplicação..."

    connection = socket.accept

    if connection == false then
        puts "Socket.accept falhou."
        break
    end

    msg = connection[0].read
    break if msg == false
    
    porta_sr = app_port
    porta_ds = 2321
    length = msg.length + 8
    aux = [porta_sr,porta_ds,length]
    checksum = checksum(aux.pack('nnn') << msg)
    aux = [porta_sr,porta_ds,length, checksum]
    segmento = aux.pack('nnnn')
    segmento = segmento << msg

    puts "Porta de Origem: #{porta_sr}"
    puts "Porta de Destino: #{porta_sr}"
    puts "Tamanho: #{length}"
    puts "Checksum: #{checksum}"

    begin
        
        puts "Enviando dados para a camada física..."

        send_socket(segmento,fscl_port)

        puts "Esperando resposta..."

        segmento = recv_socket(fssr_port)

        puts "Segmento recebido..."

        segmento = segmento[20..-1]
        udp = segmento[0..8]
        dados = udp.unpack('nnnn')
        msg = segmento[8..-1]

        puts "Validação do segmento..."

        if checksum(dados.pack('nnn') << msg) == dados[3] then
            puts "OK"
        else
            puts "Segmento ignorado"
        end

        puts "Enviando mendagem para a aplicação..."

        break if connection[0].write(msg) == false

    rescue Exception => msg
        puts "Error: #{msg}."
        break
    end

    connection[0].close
end

connection[0].close
socket.close